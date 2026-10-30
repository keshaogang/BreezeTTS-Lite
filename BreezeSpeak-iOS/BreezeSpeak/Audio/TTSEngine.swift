//
//  TTSEngine.swift
//  BreezeSpeak
//
//  推理引擎抽象。Breeze 原生能力（spk / clone / design / direction）统一收敛到 TTSRequest。
//

import Foundation

/// 采样策略：决定「同一段提示词，每次听起来是不是同一个人」，以及会不会讲一半卡住。
///
/// 引擎里这几个参数传 0 表示「沿用 gguf 里写死的值」。Breeze 的 gguf 默认是
/// 带温度的随机采样（temperature 0.9、top_k 50、**repetition_penalty 1.1**），
/// 也就是每一帧都在几十个候选 token 里掷骰子。声学 token 决定音高、共振峰、气声，
/// 骰子掷出来不一样，听感就是换了一个人——这是「提示词没变、声音却变了」的原因。
///
/// 两个独立的机制，缺一不可：
///
/// 1. **确定性 → 音色稳定**：固定 seed（4_242）后，`std::mt19937` 的随机序列可复现，
///    同一段文字逐样本一致；再配合 `VoiceAnchor` 锚点音频走克隆分支，换文字也还是同一个人。
///    注意 top_k=1 的贪心**不是**一致性的必要条件——实测固定 seed + top_k=25 一样逐样本可复现。
///
/// 2. **重复惩罚 → 不卡壳**（本次修复的关键）：codec 语言模型在贪心解码下有个陷阱——
///    一旦某一帧选中了「静音 / 填充」token，如果 repetition_penalty 关掉（=1.0），
///    采样器会对历史 token **完全不惩罚**（见引擎 sampling.cpp：`if (rep != 1.0f)` 才生效），
///    模型就会一路重复同一个静音 token，吐出 2~3 秒纯数字静音——听感正是「讲一半顿一下才说完」。
///    老的 `.locked` 把 rep 显式设成 1，恰好覆盖了 gguf 自带的 1.1，等于亲手关掉了防卡死机制。
///    恢复成 1.15 后，实测最长静音从 2.96s 降到 0.56s（正常标点停顿），仍保持贪心可复现。
struct SamplingOptions: Hashable {
    var temperature: Double
    var topK: Int
    var topP: Double
    var repetitionPenalty: Double
    var seed: Int

    /// 锁定音色：贪心 top_k=1 + 固定 seed（可复现），并**保留重复惩罚**防止静音循环。
    /// rep 必须 > 1.0：设成 1.0 会绕过引擎的重复惩罚逻辑，退化出多秒纯静音。
    static let locked = SamplingOptions(temperature: 0.9, topK: 1, topP: 1,
                                        repetitionPenalty: 1.15, seed: 4_242)

    /// 自由采样：交给 gguf 的默认温度，每次都会有些呼吸和音高的差别。
    static let free = SamplingOptions(temperature: 0, topK: 0, topP: 0,
                                      repetitionPenalty: 0, seed: 4_242)

    /// 缓存键用：任何一个参数变了都不能复用旧音频
    var cacheTag: String {
        String(format: "t%.3f|k%d|p%.3f|r%.3f|s%d",
               temperature, topK, topP, repetitionPenalty, seed)
    }
}

struct TTSRequest {
    var text: String
    var voice: VoiceProfile
    /// Voice Direction 演绎指令：控制情绪 / 语气 / 节奏，不改变声线本身
    var direction: String = ""
    var guidanceScale: Double = AppConfig.defaultGuidanceScale
    var speed: Double = AppConfig.defaultSpeed
    /// 采样策略（锁定音色 / 自由采样）
    var sampling: SamplingOptions = .locked
    /// 试听请求。试听只是听个大概，不该为它多跑一遍音色锚点，太慢。
    var isPreview: Bool = false
}

struct TTSSegment {
    var text: String
    var pauseAfter: Double
    /// 声线演绎修饰（whisper / slow / fast）
    var modifier: SpeechModifier = .none
}

enum SpeechModifier: String {
    case none, whisper, slow, fast

    var rateFactor: Double {
        switch self {
        case .none: return 1
        case .whisper: return 0.94
        case .slow: return 0.82
        case .fast: return 1.18
        }
    }

    var gainFactor: Double {
        switch self {
        case .whisper: return 0.55
        default: return 1
        }
    }
}

struct TTSResult {
    var samples: [Float]
    var sampleRate: Double

    var duration: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

enum TTSError: LocalizedError {
    case engineUnavailable
    case modelNotReady
    case emptyText
    case voiceNotFound
    case outOfMemory
    case cancelled
    case synthesisFailed(String)
    case audioUnreadable(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "神经引擎尚未就绪，当前使用系统离线语音兜底。"
        case .modelNotReady:
            return "模型尚未下载完成，请先在「模型管理」中完成下载。"
        case .emptyText:
            return "请输入要合成的文本。"
        case .voiceNotFound:
            return "找不到这条声线，它可能已经被删除了。"
        case .outOfMemory:
            return "设备可用内存不足，已中止本次推理。请关闭其他 App 后重试。"
        case .cancelled:
            return "已取消本次生成。"
        case .synthesisFailed(let message):
            return "语音合成失败：\(message)"
        case .audioUnreadable(let message):
            return "无法解析该音频：\(message)"
        case .exportFailed(let message):
            return "导出失败：\(message)"
        }
    }
}

@MainActor
protocol TTSEngine: AnyObject {
    var displayName: String { get }
    var isNeural: Bool { get }

    /// 加载模型 / 预热声纹，可在生成前调用
    func prepare(voice: VoiceProfile?) async throws

    /// 分段流式推理：每完成一段通过 onPartial 回吐累积采样，便于波形与进度实时刷新。
    /// `onChunk` 在引擎线程回调「本次新增」的采样，用于波形增量更新——
    /// 走它可以避免每次刷新都把整个累积数组复制一遍（长音频下是 O(n²) 的拷贝）。
    func synthesize(
        _ request: TTSRequest,
        onProgress: @escaping (Double) -> Void,
        onPartial: @escaping (TTSResult) -> Void,
        onChunk: ((UnsafeBufferPointer<Float>) -> Void)?
    ) async throws -> TTSResult

    /// 立刻释放模型与中间缓冲，防止 iPad 被系统杀后台
    func unload()
}

extension TTSEngine {
    /// 不需要增量波形时（兜底引擎等）可以只传三个参数
    func synthesize(
        _ request: TTSRequest,
        onProgress: @escaping (Double) -> Void,
        onPartial: @escaping (TTSResult) -> Void
    ) async throws -> TTSResult {
        try await synthesize(request, onProgress: onProgress, onPartial: onPartial, onChunk: nil)
    }
}

enum TTSEngineAvailability {
    /// 是否链接了 MLXAudio 框架
    static var mlxLinked: Bool {
        #if canImport(MLXAudio)
        return true
        #else
        return false
        #endif
    }
}
