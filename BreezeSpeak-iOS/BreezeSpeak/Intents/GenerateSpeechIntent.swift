//
//  GenerateSpeechIntent.swift
//  BreezeSpeak
//
//  系统「快捷指令」Action：外部传入文字 / 声线 / 演绎指令，直接离线生成播报音频。
//  支持在快捷指令里串接「保存到文件」「播放」「隔空投送」。
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - 声线实体

/// 让「声线」在快捷指令里变成一个可点选的下拉列表，
/// 而不是让人手打名字或 UUID。
struct VoiceChoice: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "声线")
    static var defaultQuery = VoiceChoiceQuery()

    /// 用 UUID 字符串作为稳定标识；内置声线也各自有固定 UUID
    var id: String
    var name: String
    var subtitleText: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitleText)"
        )
    }

    init(profile: VoiceProfile) {
        self.id = profile.id.uuidString
        self.name = profile.displayName
        self.subtitleText = profile.subtitle.isEmpty ? profile.kind.title : profile.subtitle
    }
}

struct VoiceChoiceQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [VoiceChoice] {
        let store = VoiceStore()
        return identifiers.compactMap { raw in
            if let uuid = UUID(uuidString: raw), let voice = store.voice(id: uuid) {
                return VoiceChoice(profile: voice)
            }
            return store.allVoices
                .first { $0.displayName == raw }
                .map(VoiceChoice.init(profile:))
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [VoiceChoice] {
        VoiceStore().allVoices.map(VoiceChoice.init(profile:))
    }

    @MainActor
    func defaultResult() async -> VoiceChoice? {
        VoiceChoice(profile: VoiceStore().defaultVoice)
    }
}

// MARK: - Intent

struct GenerateSpeechIntent: AppIntent {
    static var title: LocalizedStringResource = "生成播报音频"
    static var description = IntentDescription(
        "用 BreezeSpeak 在本机离线合成语音，返回 WAV 文件。不联网、不上传文本。",
        categoryName: "语音合成"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "文本", description: "要朗读的内容，支持 | || (slow) (whisper) 等原生标记")
    var text: String

    @Parameter(title: "声线", description: "留空用默认声线")
    var voice: VoiceChoice?

    @Parameter(title: "演绎指令", description: "例如：温柔一点，语速稍慢")
    var direction: String?

    /// 可选覆盖：留空就用声线自己存着的语速。
    @Parameter(title: "语速倍率", description: "0.7 ~ 1.3。留空沿用声线设置")
    var speed: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("用 BreezeSpeak 朗读 \(\.$text)") {
            \.$voice
            \.$direction
            \.$speed
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<IntentFile> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TTSError.emptyText
        }

        let store = VoiceStore()
        let model = ModelManager()
        let runtime = SpeechRuntime(model: model)

        // 权重没下载就明确报错，不要拖到引擎里再失败
        guard model.isReady else {
            throw TTSError.modelNotReady
        }

        let profile = resolveVoice(in: store)
        let request = TTSRequest(
            text: trimmed,
            voice: profile,
            direction: (direction ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            guidanceScale: profile.guidanceScale,
            speed: speed.map { min(max($0, 0.7), 1.3) } ?? profile.speed
        )

        let result = try await runtime.synthesize(request, onProgress: { _ in }, onPartial: { _ in })
        runtime.trimMemory()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "BreezeSpeak_\(formatter.string(from: Date())).wav"
        let url = AppPaths.exportDirectory.appendingPathComponent(fileName)

        guard WAVFile.write(samples: result.samples, sampleRate: result.sampleRate, to: url) else {
            throw TTSError.exportFailed("无法写入沙盒")
        }

        let file = IntentFile(fileURL: url, filename: fileName, type: .wav)
        return .result(
            value: file,
            dialog: IntentDialog("已生成 \(String(format: "%.1f", result.duration)) 秒音频，声线：\(profile.displayName)")
        )
    }

    @MainActor
    private func resolveVoice(in store: VoiceStore) -> VoiceProfile {
        guard let chosen = voice else { return store.defaultVoice }
        if let uuid = UUID(uuidString: chosen.id), let profile = store.voice(id: uuid) {
            return profile
        }
        if let profile = store.allVoices.first(where: { $0.displayName == chosen.name }) {
            return profile
        }
        return store.defaultVoice
    }
}
