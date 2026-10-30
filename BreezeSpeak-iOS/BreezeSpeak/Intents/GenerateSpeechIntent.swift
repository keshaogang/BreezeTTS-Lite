//
//  GenerateSpeechIntent.swift
//  BreezeSpeak
//
//  系统「快捷指令」Action：外部传入文字 / 声线 ID / 演绎指令，直接离线生成播报音频。
//  支持在快捷指令里串接「保存到文件」「播放」「隔空投送」。
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

struct GenerateSpeechIntent: AppIntent {
    static var title: LocalizedStringResource = "生成播报音频"
    static var description = IntentDescription(
        "用 BreezeSpeak 在本机离线合成语音，返回 WAV 文件。不联网、不上传文本。",
        categoryName: "语音合成"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "文本", description: "要朗读的内容，支持 | || (slow) (whisper) 等原生标记")
    var text: String

    @Parameter(title: "声线", description: "声线名称或 ID，例如「清风」「沉稳」；留空用默认声线")
    var voiceID: String?

    @Parameter(title: "演绎指令", description: "例如：温柔一点，语速稍慢")
    var direction: String?

    static var parameterSummary: some ParameterSummary {
        Summary("用 BreezeSpeak 朗读 \(\.$text)") {
            \.$voiceID
            \.$direction
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<IntentFile> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TTSError.emptyText
        }

        let voices = VoiceStore()
        let model = ModelManager()
        let runtime = SpeechRuntime(model: model)

        let voice = resolveVoice(in: voices)
        let request = TTSRequest(
            text: trimmed,
            voice: voice,
            direction: (direction ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            guidanceScale: voice.guidanceScale,
            speed: AppConfig.defaultSpeed
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
            dialog: IntentDialog("已生成 \(String(format: "%.1f", result.duration)) 秒音频，声线：\(voice.displayName)")
        )
    }

    @MainActor
    private func resolveVoice(in voices: VoiceStore) -> VoiceProfile {
        guard let raw = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return voices.defaultVoice
        }
        if let uuid = UUID(uuidString: raw), let voice = voices.voice(id: uuid) {
            return voice
        }
        if let voice = voices.allVoices.first(where: { $0.displayName == raw }) {
            return voice
        }
        return voices.defaultVoice
    }
}

struct BreezeSpeakShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateSpeechIntent(),
            phrases: [
                "用 \(.applicationName) 生成播报",
                "让 \(.applicationName) 朗读这段话",
                "用 \(.applicationName) 生成语音"
            ],
            shortTitle: "生成播报音频",
            systemImageName: "waveform"
        )
    }
}
