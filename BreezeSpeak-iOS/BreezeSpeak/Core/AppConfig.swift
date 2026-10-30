//
//  AppConfig.swift
//  BreezeSpeak
//
//  全局常量、模型信息与沙盒路径。
//  纯离线：所有资源只落在 App 沙盒内，不存在任何上报 / 登录 / 远端接口。
//

import Foundation

enum AppConfig {
    static let appName = "BreezeSpeak"
    static let tagline = "本地离线语音合成"

    // MARK: - 模型

    /// 与 macOS 版同源：同一份 GGUF 权重、同一套 C++ 推理核心（ggml + Metal）。
    static let modelDisplayName = "Breeze TTS 2"
    /// 国内可达的镜像优先，官方仓库作为备用
    static let modelMirrorBase = "https://hf-mirror.com/HoppouAI/Breeze-TTS-2.cpp/resolve/main"
    static let modelUpstreamBase = "https://huggingface.co/HoppouAI/Breeze-TTS-2.cpp/resolve/main"
    static let modelFolderName = "Breeze-TTS-2-gguf"

    /// 默认档位：体积与内存的平衡点，8 GB 的 iPad Air 也能稳住
    static let defaultTierID = "q4_k"

    // MARK: - 音频

    static let sampleRate: Double = 24_000
    static let bitDepth: Int = 16
    static let segmentCharLimit = 88
    static let shortPauseSeconds: Double = 0.18
    static let longPauseSeconds: Double = 0.46
    static let crossfadeSeconds: Double = 0.012

    // MARK: - 声线

    static let maxCloneVoices = 12
    static let minReferenceSeconds: Double = 3
    static let maxReferenceSeconds: Double = 30
    /// 引擎原生只有一个基础音色（[S0]），其余音色由「声音描述 + 参考音频」生成，
    /// 所以这里的 guidance 直接映射成引擎的 cfg_scale。
    static let defaultGuidanceScale: Double = 1.0
    static let guidanceRange: ClosedRange<Double> = 1...6
    static let defaultSpeed: Double = 1.05

    /// 声码器一次解码多少帧（25 帧 ≈ 1 秒音频）。0 = 引擎默认的流式分块。
    ///
    /// 引擎默认是「先来一小块，再来 25 帧一块」的流式节奏，好处是出声快，
    /// 代价是每块都要把前文 `sliding_window + 16`（88 帧）重新解码一遍 ——
    /// 摊到每块上相当于多算三倍。本 App 是整段生成完再播，不需要边生成边出声，
    /// 所以把整段一次解码掉，省下这部分重复计算。
    /// 每帧 1920 采样 / 24 kHz = 80ms，所以 240 帧 ≈ **19.2 秒**音频：
    /// 常见短句一次解码就结束（省掉绝大部分重复计算），
    /// 长文按 19.2 秒切片，块不至于大到把激活占满内存。
    static var decodeChunkFrames: Int {
        if let raw = ProcessInfo.processInfo.environment["BREEZESPEAK_CHUNK"],
           let value = Int(raw) {
            return value
        }
        return 240
    }

    /// 长文本分段阈值（引擎的加权字符数：ASCII 算 1，CJK 算 3）。
    ///
    /// 引擎源码里 `GenRequest::split_chars` 的默认值是 600，注释写得很清楚：
    /// 「the model loses track of the text past about a minute of audio」——
    /// 超过约一分钟音频后模型会跟丢文本。600 加权字 ≈ 200 个汉字 ≈ 40 秒音频，
    /// 正好留出余量。
    ///
    /// 为什么不能传 0：0 在引擎里表示「不分段，整段一次推完」。长文本一次推会踩两个雷：
    ///   1) 文本编码器要给整段文本建 `T×T` 的两张注意力 mask（`text_encoder.cpp` 里
    ///      `build_bidirectional_mask(T, T, …)` 调用两次）外加每层 `T×T` 的注意力分数，
    ///      内存是 **T 的平方** 增长 —— 几千字就是几百 MB，iPad 上直接分配失败；
    ///   2) 单次生成还有 `max_new_tokens` 上限（gguf 默认 750 帧 × 80ms = 60 秒音频），
    ///      超出的部分会被静默截断。
    /// 这两点合起来就是「长文本生成失败」的根因。
    ///
    /// 分段后每段都以同一条参考音频 + 同一个 seed 起跑，音色不会在接缝处漂移。
    static var splitChars: Int {
        if let raw = ProcessInfo.processInfo.environment["BREEZESPEAK_SPLIT"],
           let value = Int(raw) {
            return value
        }
        return 600
    }
    static let speedRange: ClosedRange<Double> = 0.7...1.3

    // MARK: - 历史

    static let maxHistoryItems = 200
}

enum AppPaths {
    private static let fm = FileManager.default

    static var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var support: URL {
        let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BreezeSpeak", isDirectory: true)
        ensure(url)
        return url
    }

    /// 沙盒根（模型 / 声纹 / 元数据）
    static var root: URL { support }

    static var modelDirectory: URL {
        let url = root.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(AppConfig.modelFolderName, isDirectory: true)
        ensure(url)
        return url
    }

    static var embeddingsDirectory: URL {
        let url = root.appendingPathComponent("Embeddings", isDirectory: true)
        ensure(url)
        return url
    }

    static var referencesDirectory: URL {
        let url = root.appendingPathComponent("References", isDirectory: true)
        ensure(url)
        return url
    }

    /// 历史与导出音频放在 Documents，便于通过「文件」App 直接取用。
    static var audioDirectory: URL {
        let url = documents.appendingPathComponent("BreezeSpeak/Audio", isDirectory: true)
        ensure(url)
        return url
    }

    static var exportDirectory: URL {
        let url = documents.appendingPathComponent("BreezeSpeak/Exports", isDirectory: true)
        ensure(url)
        return url
    }

    /// 推理速度流水，放在 Documents 里，方便用「文件」App 或 devicectl 取回
    static var performanceLogFile: URL {
        documents.appendingPathComponent("BreezeSpeak/performance.log")
    }

    static var voicesFile: URL { root.appendingPathComponent("voices.json") }
    static var historyFile: URL { root.appendingPathComponent("history.json") }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    /// 同输入复用的音频缓存：同一段文字 + 同一声线必然得到同一份音频，
    /// 既保证「同一提示词声音一致」，命中时也不消耗推理时间。
    static var audioCacheDirectory: URL {
        let url = root.appendingPathComponent("AudioCache", isDirectory: true)
        ensure(url)
        return url
    }
    static var downloadStateDirectory: URL {
        let url = root.appendingPathComponent("Downloads", isDirectory: true)
        ensure(url)
        return url
    }

    static func ensure(_ url: URL) {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func relativePath(of url: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    static func resolve(relative path: String) -> URL {
        root.appendingPathComponent(path)
    }

    static func bytes(at url: URL) -> Int64 {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return 0 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

enum TimeFormat {
    static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 1 { return String(format: "%.2f 秒", seconds) }
        if seconds < 60 { return String(format: "%.1f 秒", seconds) }
        return mmss(seconds)
    }

    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }
}
