//
//  AudioCache.swift
//  BreezeSpeak
//
//  同输入复用音频：同一段文字 + 同一条声线 + 同一组参数，第二次生成直接取上次的结果。
//
//  为什么要有它，三个理由：
//  1. **声音一致性**。「锁定音色」开着时采样已经是逐帧贪心的（top_k = 1），
//     同一段文字本来就该逐样本一致；缓存再兜一层，连浮点累加顺序带来的末位差异
//     都不必担心。关掉锁定（自由采样）时，缓存这一层更是唯一的一致性来源。
//  2. **速度**。重复生成同一段文本（改标点后再试、批量重播同一句）直接命中，
//     不需要再跑一遍推理。
//  3. **省电**。命中时一行推理都不跑，iPad 不发热、不掉频。
//
//  键包含声线 id、采样策略与全部可调参数，任何一项变化都会落到新的文件，不会串音。
//

import CryptoKit
import Foundation

enum AudioCache {
    /// 缓存条目上限。一段 10 秒音频约 480 KB，120 条 ≈ 56 MB，够用又不占地方。
    private static let maxEntries = 120

    /// 命中时打日志用的开关，方便实测验证
    private(set) static var lastHit = false

    static func key(for request: TTSRequest) -> String {
        let parts: [String] = [
            request.text,
            request.voice.id.uuidString,
            request.voice.referenceFileName ?? "-",
            request.voice.referenceText ?? "-",
            String(format: "g%.3f", request.guidanceScale),
            String(format: "s%.3f", request.speed),
            request.direction,
            String(format: "v%.3f", request.voice.speed),
            request.voice.descriptor,
            // 采样策略也算输入：锁定音色与自由采样出来的音频不是同一个东西，
            // 不带上它，切换开关后会错复用上一次的旧音频。
            request.sampling.cacheTag,
            // 有没有音色锚点同样是输入：锚点前与锚点后是两个不同的声音。
            VoiceAnchor.exists(for: request.voice) ? "anchor" : "plain"
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func load(key: String, sampleRate: Double) -> TTSResult? {
        let url = AppPaths.audioCacheDirectory.appendingPathComponent("\(key).wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastHit = false
            return nil
        }
        guard let result = try? WAVFile.read(url: url), !result.samples.isEmpty else {
            lastHit = false
            return nil
        }
        // 刷新一次修改时间，让 LRU 清理时把它当成「最近用过」
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        lastHit = true
        return result
    }

    static func store(_ result: TTSResult, key: String) {
        let url = AppPaths.audioCacheDirectory.appendingPathComponent("\(key).wav")
        guard WAVFile.write(samples: result.samples, sampleRate: result.sampleRate, to: url) else { return }
        evictIfNeeded()
    }

    /// 超出上限时按修改时间淘汰最旧的（LRU 的近似做法，够用且无额外状态）
    private static func evictIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: AppPaths.audioCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        guard files.count > maxEntries else { return }

        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l < r
        }
        for url in sorted.prefix(files.count - maxEntries) {
            try? fm.removeItem(at: url)
        }
    }

    static func clear() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: AppPaths.audioCacheDirectory,
                                                     includingPropertiesForKeys: nil,
                                                     options: .skipsHiddenFiles) else { return }
        for url in files { try? fm.removeItem(at: url) }
    }

    static var sizeBytes: Int64 { AppPaths.directorySize(AppPaths.audioCacheDirectory) }
    static var count: Int {
        (try? FileManager.default.contentsOfDirectory(at: AppPaths.audioCacheDirectory,
                                                      includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles).count) ?? 0
    }
}
