//
//  VoiceProfile.swift
//  BreezeSpeak
//
//  声线模型：内置音色 / 声音克隆 / 文字造声 三类共用一份结构。
//  克隆与 Design 的“声纹”以 VoiceSignature（可序列化 embedding 摘要）落盘缓存，
//  再次选用时无需重新计算。
//

import Foundation

enum VoiceKind: String, Codable, CaseIterable, Hashable {
    case builtin
    case clone
    case design

    var title: String {
        switch self {
        case .builtin: return "内置"
        case .clone: return "克隆"
        case .design: return "造声"
        }
    }

    var systemImage: String {
        switch self {
        case .builtin: return "waveform"
        case .clone: return "waveform.badge.mic"
        case .design: return "sparkles"
        }
    }
}

/// 声纹参数摘要（embedding 的可读表征）。
/// 神经引擎会把完整 embedding 存成独立文件，这里保存跨引擎共用的关键参数，
/// 让系统兜底引擎也能渲染出可区分的音色。
struct VoiceSignature: Codable, Hashable {
    var seed: UInt64
    /// 基频倍率 0.6 ~ 1.6
    var pitch: Double
    /// 语速倍率 0.85 ~ 1.15
    var rate: Double
    /// 明亮度（频谱重心）0 ~ 1
    var brightness: Double
    /// 气声比例 0 ~ 1
    var breathiness: Double
    /// 音量增益 0.7 ~ 1.0
    var gain: Double

    static let neutral = VoiceSignature(seed: 0, pitch: 1, rate: 1, brightness: 0.5, breathiness: 0.2, gain: 0.95)
}

struct VoiceProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: VoiceKind
    /// 内置音色的原生标识（历史数据里保留，本引擎不再用 spk 选音色）
    var spk: String?
    /// 造声描述 / 克隆备注
    var descriptor: String = ""
    /// 内置音色自带的英文声音描述，直接作为引擎 instruction
    var nativeInstruction: String?
    var signature: VoiceSignature
    var guidanceScale: Double = AppConfig.defaultGuidanceScale
    var speed: Double = AppConfig.defaultSpeed
    var defaultDirection: String = ""
    /// 克隆时的参考音频原话
    var referenceText: String?
    /// 克隆声线的文字微调：音色由参考音频决定，这段话只调整语气、语速、气息。
    /// 用可选类型是为了和旧版本存档兼容（老数据里没有这个键）。
    var tweak: String?
    var referenceFileName: String?
    var referenceDuration: Double?
    var createdAt: Date = Date()
    /// 声纹缓存文件名（Embeddings 目录下）
    var embeddingFileName: String?

    var subtitle: String {
        switch kind {
        case .builtin:
            return descriptor
        case .clone:
            if let duration = referenceDuration {
                return "声音克隆 · 参考 \(TimeFormat.duration(duration))"
            }
            return "声音克隆"
        case .design:
            return descriptor.isEmpty ? "文字造声" : descriptor
        }
    }

    var shortDescriptor: String {
        switch kind {
        case .builtin: return "内置"
        case .clone: return referenceText?.isEmpty == false ? "参考文稿 \(referenceText!.count) 字" : "参考音频"
        case .design: return "guidance \(String(format: "%.1f", guidanceScale))"
        }
    }

    var displayName: String { name.isEmpty ? kind.title + "声线" : name }
}

// MARK: - 内置音色

extension VoiceProfile {
    /// 引擎原生只有 [S0] 一个基础音色，五个「内置音色」是靠声音描述造出来的五条固定声线，
    /// 与 Mac 版的 voice design 走的是同一条路径，不需要额外权重。
    static let builtins: [VoiceProfile] = [
        makeBuiltin(index: 0,
                    id: "A1000000-0000-4000-8000-000000000001",
                    name: "清风",
                    descriptor: "清亮女声 · 日常播报",
                    instruction: "A clear, bright young woman with a light, friendly delivery. Natural everyday speaking pace."),
        makeBuiltin(index: 1,
                    id: "A1000000-0000-4000-8000-000000000002",
                    name: "沉稳",
                    descriptor: "低沉男声 · 新闻播报",
                    instruction: "A calm, low-pitched man in his forties, crisp articulation, even rhythm, like a documentary narrator."),
        makeBuiltin(index: 2,
                    id: "A1000000-0000-4000-8000-000000000003",
                    name: "温言",
                    descriptor: "温柔女声 · 助眠朗读",
                    instruction: "A soft, warm woman speaking gently and slowly, close to the microphone, soothing bedtime reading."),
        makeBuiltin(index: 3,
                    id: "A1000000-0000-4000-8000-000000000004",
                    name: "轻快",
                    descriptor: "明亮童声 · 提示音",
                    instruction: "A bright, cheerful child-like voice, higher pitch, quick and playful, short sentences."),
        makeBuiltin(index: 4,
                    id: "A1000000-0000-4000-8000-000000000005",
                    name: "夜语",
                    descriptor: "气声低语 · 私密播报",
                    instruction: "A hushed, breathy whisper close to the ear, low volume, intimate late-night delivery.")
    ]

    private static func makeBuiltin(index: Int, id: String, name: String, descriptor: String, instruction: String) -> VoiceProfile {
        let pitches: [Double] = [1.14, 0.82, 1.05, 1.26, 0.94]
        let rates: [Double] = [1.03, 0.96, 0.94, 1.08, 0.92]
        let brightness: [Double] = [0.72, 0.34, 0.52, 0.86, 0.28]
        let breathiness: [Double] = [0.16, 0.22, 0.30, 0.12, 0.66]
        return VoiceProfile(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            kind: .builtin,
            spk: nil,
            descriptor: descriptor,
            nativeInstruction: instruction,
            signature: VoiceSignature(
                seed: UInt64(index) &+ 1,
                pitch: pitches[index],
                rate: rates[index],
                brightness: brightness[index],
                breathiness: breathiness[index],
                gain: index == 4 ? 0.78 : 0.95
            )
        )
    }
}

// MARK: - 提示词模板

struct PromptTemplate: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var systemImage: String
    var text: String

    static let all: [PromptTemplate] = [
        PromptTemplate(title: "日常通知", systemImage: "bell", text: "提醒，| 定时任务已经到时间。"),
        PromptTemplate(title: "沉稳播报", systemImage: "dot.radiowaves.left.and.right", text: "音频生成完成，|| 可以开始播放。"),
        PromptTemplate(title: "简短提示", systemImage: "checkmark.circle", text: "任务已保存。"),
        PromptTemplate(title: "轻声模式", systemImage: "speaker.wave.1", text: "(whisper) 音频正在后台生成。"),
        PromptTemplate(title: "慢速朗读", systemImage: "tortoise", text: "(slow) 请仔细阅读下面的内容。")
    ]
}
