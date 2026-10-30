//
//  VoiceSignatureFactory.swift
//  BreezeSpeak
//
//  声纹生成与缓存。
//  · 克隆：从参考音频量出基频 / 明亮度 / 气声 / 语速，映射为可复用的声纹摘要
//  · 造声：把文字描述解析成音色参数，guidance_scale 控制贴合强度
//  摘要（embedding 的索引）写入沙盒，选声线时直接命中缓存，不重复计算。
//

import Foundation

enum VoiceSignatureFactory {

    // MARK: - 文字造声

    private struct Trait {
        var keywords: [String]
        var pitch: Double?
        var rate: Double?
        var brightness: Double?
        var breathiness: Double?

        init(keywords: [String], pitch: Double? = nil, rate: Double? = nil, brightness: Double? = nil, breathiness: Double? = nil) {
            self.keywords = keywords
            self.pitch = pitch
            self.rate = rate
            self.brightness = brightness
            self.breathiness = breathiness
        }
    }

    private static let traits: [Trait] = [
        Trait(keywords: ["女", "女性", "女生", "女子"], pitch: 1.22),
        Trait(keywords: ["男", "男性", "男生", "男子"], pitch: 0.86),
        Trait(keywords: ["童", "小孩", "儿童", "少女"], pitch: 1.34, brightness: 0.8),
        Trait(keywords: ["老人", "年长", "老年", "爷爷", "奶奶"], pitch: 0.94, rate: 0.92),
        Trait(keywords: ["低沉", "低音", "厚重", "磁性"], pitch: 0.82, brightness: 0.4),
        Trait(keywords: ["清亮", "明亮", "清脆", "甜美", "甜"], brightness: 0.86),
        Trait(keywords: ["沙哑", "烟嗓", "颗粒"], brightness: 0.32, breathiness: 0.58),
        Trait(keywords: ["温柔", "柔和", "软"], rate: 0.95, brightness: 0.55, breathiness: 0.4),
        Trait(keywords: ["气声", "耳语", "低语", "私语"], breathiness: 0.88),
        Trait(keywords: ["沉稳", "冷静", "新闻", "播音", "严肃"], rate: 0.97, brightness: 0.5, breathiness: 0.18),
        Trait(keywords: ["活泼", "轻快", "俏皮", "元气"], rate: 1.1, brightness: 0.78),
        Trait(keywords: ["南方", "台湾", "港台", "软糯"], pitch: 1.08, rate: 0.95),
        Trait(keywords: ["北方", "标准", "普通话", "播音腔"], rate: 1.0, brightness: 0.58),
        Trait(keywords: ["嘶", "气息", "喘息"], breathiness: 0.7),
        Trait(keywords: ["明亮", "通透"], brightness: 0.8)
    ]

    /// 文字造声：描述 + guidance → 声纹
    static func makeDesign(description: String, guidance: Double) -> VoiceSignature {
        var pitch = 1.0
        var rate = 1.0
        var brightness = 0.5
        var breathiness = 0.22
        var hits = 0

        for trait in traits where trait.keywords.contains(where: { description.contains($0) }) {
            hits += 1
            if let value = trait.pitch { pitch = (pitch + value) / 2 }
            if let value = trait.rate { rate = (rate + value) / 2 }
            if let value = trait.brightness { brightness = (brightness + value) / 2 }
            if let value = trait.breathiness { breathiness = (breathiness + value) / 2 }
        }

        // guidance 越大越贴近描述；越小越接近中性
        let strength = min(1.0, max(0.35, 0.42 + guidance * 0.095))
        pitch = 1 + (pitch - 1) * strength
        rate = 1 + (rate - 1) * strength
        brightness = 0.5 + (brightness - 0.5) * strength
        breathiness = 0.22 + (breathiness - 0.22) * strength

        let seed = stableHash(description + String(format: "%.2f", guidance) + (hits > 0 ? "hit" : "neutral"))
        // 描述无命中关键词时给一点稳定的个体差异，避免所有声线一模一样
        let jitter: Double = hits > 0 ? 0.015 : 0.06
        let lowValue: Double = Double((seed & 0xFF) % 100)
        let highValue: Double = Double(((seed >> 8) & 0xFF) % 100)
        pitch += lowValue / 100 * jitter
        brightness = clamp(brightness + highValue / 100 * jitter * 0.6, 0, 1)

        return VoiceSignature(
            seed: seed,
            pitch: clamp(pitch, 0.6, 1.6),
            rate: clamp(rate, 0.85, 1.15),
            brightness: clamp(brightness, 0, 1),
            breathiness: clamp(breathiness, 0, 1),
            gain: clamp(0.96 - breathiness * 0.18, 0.7, 1.0)
        )
    }

    // MARK: - 声音克隆

    static func makeClone(samples: [Float], sampleRate: Double, transcript: String) -> VoiceSignature {
        let f0 = AudioAnalysis.estimatePitch(samples, sampleRate: sampleRate) ?? 190
        let pitch = clamp(f0 / 195.0, 0.62, 1.58)
        let brightness = AudioAnalysis.brightness(samples, sampleRate: sampleRate)
        let snr = AudioAnalysis.snrDB(samples, sampleRate: sampleRate)
        let breathiness = clamp(1 - (snr - 6) / 30, 0.05, 0.9)

        let speechSeconds = max(0.5, Double(samples.count) / sampleRate * max(0.35, AudioAnalysis.speechRatio(samples, sampleRate: sampleRate)))
        let charCount = max(1, TextSegmenter.plainText(transcript).count)
        let charsPerSecond = Double(charCount) / speechSeconds
        let rate = clamp(charsPerSecond / 4.6, 0.85, 1.15)

        let rms = AudioAnalysis.rms(samples)
        let gain = clamp(Double(rms) * 3.4, 0.7, 1.0)

        return VoiceSignature(
            seed: stableHash(transcript + "\(samples.count)"),
            pitch: pitch,
            rate: rate,
            brightness: brightness,
            breathiness: breathiness,
            gain: gain
        )
    }

    // MARK: - 缓存

    /// 声纹摘要落盘（Embeddings/<voiceID>.json），命中即复用
    @discardableResult
    static func persist(_ signature: VoiceSignature, for voiceID: UUID, extra: [String: String] = [:]) -> String? {
        let fileName = "\(voiceID.uuidString).json"
        let payload: [String: Any] = [
            "seed": signature.seed,
            "pitch": signature.pitch,
            "rate": signature.rate,
            "brightness": signature.brightness,
            "breathiness": signature.breathiness,
            "gain": signature.gain,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "note": extra
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return nil
        }
        let url = AppPaths.embeddingsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    static func load(forEmbeddingFile fileName: String?) -> VoiceSignature? {
        guard let fileName else { return nil }
        let url = AppPaths.embeddingsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func double(_ key: String) -> Double { (object[key] as? NSNumber)?.doubleValue ?? 0 }
        let seed = UInt64((object["seed"] as? NSNumber)?.uint64Value ?? 0)
        return VoiceSignature(
            seed: seed,
            pitch: double("pitch"),
            rate: double("rate"),
            brightness: double("brightness"),
            breathiness: double("breathiness"),
            gain: double("gain")
        )
    }

    // MARK: - 工具

    static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

// MARK: - 克隆校验

enum CloneIssue: Identifiable, Hashable {
    case tooShort(Double)
    case tooLong(Double)
    case tooNoisy(Double)
    case transcriptMismatch(expected: Double, actual: Double)

    var id: String { message }

    var title: String {
        switch self {
        case .tooShort: return "参考音频太短"
        case .tooLong: return "参考音频过长"
        case .tooNoisy: return "背景噪音过高"
        case .transcriptMismatch: return "文稿与音频不匹配"
        }
    }

    var message: String {
        switch self {
        case .tooShort(let duration):
            return String(format: "当前仅 %.1f 秒。请录制 3~30 秒连续朗读，音色特征才足够稳定。", duration)
        case .tooLong(let duration):
            return String(format: "当前 %.1f 秒，超出 30 秒上限。请截取一段自然连贯的朗读。", duration)
        case .tooNoisy(let snr):
            return String(format: "估计信噪比 %.0f dB，环境噪音会污染声纹。请在安静环境重录，或换一段干净音频。", snr)
        case .transcriptMismatch(let expected, let actual):
            return String(format: "参考文稿约需 %.1f 秒，音频实际 %.1f 秒，差距过大。请填写音频里真实的原话。", expected, actual)
        }
    }

    var isBlocking: Bool {
        switch self {
        case .tooShort, .tooLong, .transcriptMismatch: return true
        case .tooNoisy: return true
        }
    }
}

struct CloneAnalysis {
    var duration: Double
    var snr: Double
    var pitch: Double?
    var speechRatio: Double
    var issues: [CloneIssue]

    var isAcceptable: Bool { issues.filter(\.isBlocking).isEmpty }
}

enum CloneValidator {
    static func analyze(samples: [Float], sampleRate: Double, transcript: String) -> CloneAnalysis {
        let duration = Double(samples.count) / max(1, sampleRate)
        let snr = AudioAnalysis.snrDB(samples, sampleRate: sampleRate)
        let pitch = AudioAnalysis.estimatePitch(samples, sampleRate: sampleRate)
        let ratio = AudioAnalysis.speechRatio(samples, sampleRate: sampleRate)

        var issues: [CloneIssue] = []
        if duration < AppConfig.minReferenceSeconds {
            issues.append(.tooShort(duration))
        }
        if duration > AppConfig.maxReferenceSeconds {
            issues.append(.tooLong(duration))
        }
        if snr < 11 {
            issues.append(.tooNoisy(snr))
        }

        let expected = TextSegmenter.estimatedSpeechSeconds(transcript)
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let voicedDuration = max(0.6, duration * max(0.45, ratio))
            let ratioValue = voicedDuration / expected
            if ratioValue > 2.1 || ratioValue < 0.46 {
                issues.append(.transcriptMismatch(expected: expected, actual: voicedDuration))
            }
        }

        return CloneAnalysis(duration: duration, snr: snr, pitch: pitch, speechRatio: ratio, issues: issues)
    }
}
