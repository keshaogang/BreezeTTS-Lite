//
//  VoiceAnchor.swift
//  BreezeSpeak
//
//  音色锚定：把「这条声线」第一次出声的样子存成参考音频，之后每次都拿它去克隆。
//
//  为什么需要它：
//  引擎的采样只能保证「同一段文字」可复现（固定 seed + 逐帧贪心）。
//  一旦换了文字，条件上下文就变了，模型会沿着另一条轨迹重新"想"一个说话人——
//  实测同一段声音描述、两段不同文字，基频中位数能从 226 Hz 跳到 308 Hz，
//  频谱包络相似度只有 0.63，听感就是换了个人。
//
//  真正的解法是把音色钉成参考音频（ref_audio + ref_text）：
//  第一次用某条声线时先用一句固定的话生成一遍，把结果存下来，
//  之后所有生成都带着这段参考走克隆分支，音色由参考音频决定，
//  不再由这次的文字决定。锚点只在声线描述/强度/语速变化时才失效重做。
//

import CryptoKit
import Foundation

enum VoiceAnchor {
    /// 固定锚点文稿。十几二十字刚好 4~5 秒：
    /// 太短音色不稳，太长则每次生成的前缀都变重——参考音频的长短直接决定推理开销。
    static let anchorText = "这是固定音色的样本，请保持这个声音。"

    /// 参考音频上限。锚点本身就够短，这里再兜一层，防止极端语速下拖慢每次生成。
    static let maxSeconds: Double = 8

    private static var directory: URL {
        let url = AppPaths.support.appendingPathComponent("Anchors", isDirectory: true)
        AppPaths.ensure(url)
        return url
    }

    static func audioURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).wav")
    }

    static func metaURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private struct Meta: Codable {
        var text: String
        var fingerprint: String
        var duration: Double
    }

    /// 声线身份指纹：描述、指导强度、语速任一变化都算「换了一个音色」，锚点要重做。
    static func fingerprint(for voice: VoiceProfile) -> String {
        let raw = [
            voice.kind.rawValue,
            voice.descriptor,
            voice.nativeInstruction ?? "-",
            String(format: "g%.3f", voice.guidanceScale),
            String(format: "s%.3f", voice.speed),
            // 锚点文稿本身变了（换文案版本）也要重打
            anchorText,
            // 采样策略也算身份的一部分：锚点是拿 `.locked` 采样生成的参考音频。
            // 早期版本把 repetitionPenalty 关成 1.0，退化出过带 2~3 秒纯静音的坏锚点，
            // 会一直被当参考音频、把停顿和音色偏差传染给之后每次生成。
            // 把采样指纹纳入后，参数一变旧锚点自动作废重建（新锚点还会再走一遍静音兜底）。
            SamplingOptions.locked.cacheTag
        ].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 锚点是否可用（文件在、且和当前声线身份对得上）
    static func exists(for voice: VoiceProfile) -> Bool {
        guard FileManager.default.fileExists(atPath: audioURL(voice.id).path),
              let data = try? Data(contentsOf: metaURL(voice.id)),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return false }
        return meta.fingerprint == fingerprint(for: voice)
    }

    /// 读出锚点采样与它对应的文稿
    static func load(for voice: VoiceProfile) -> (samples: [Float], text: String)? {
        guard exists(for: voice),
              let data = try? Data(contentsOf: metaURL(voice.id)),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              let decoded = try? WAVFile.read(url: audioURL(voice.id)),
              !decoded.samples.isEmpty else { return nil }
        let capped = Array(decoded.samples.prefix(Int(maxSeconds * AppConfig.sampleRate)))
        guard !capped.isEmpty else { return nil }
        return (capped, meta.text)
    }

    /// 存下这次的生成结果作为锚点
    static func store(_ result: TTSResult, for voice: VoiceProfile) {
        let samples = Array(result.samples.prefix(Int(maxSeconds * AppConfig.sampleRate)))
        // 太短的锚点做参考会失真，宁可不落盘、下次再来
        guard samples.count > Int(AppConfig.sampleRate * 1.5) else { return }
        guard WAVFile.write(samples: samples, sampleRate: result.sampleRate,
                            to: audioURL(voice.id)) else { return }
        let meta = Meta(text: anchorText,
                        fingerprint: fingerprint(for: voice),
                        duration: Double(samples.count) / result.sampleRate)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL(voice.id))
        }
    }

    static func invalidate(_ id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(id))
        try? FileManager.default.removeItem(at: metaURL(id))
    }
}
