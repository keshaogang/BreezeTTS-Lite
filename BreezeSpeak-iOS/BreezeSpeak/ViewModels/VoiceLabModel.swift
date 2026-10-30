//
//  VoiceLabModel.swift
//  BreezeSpeak
//
//  声线实验室：克隆声纹提取、文字造声、试听。生成结果先做草稿，命名后再入库。
//

import Foundation
import SwiftUI

@MainActor
final class VoiceLabModel: ObservableObject {
    // 克隆
    @Published var importURL: URL?
    @Published var importFileName: String = ""
    @Published var referenceText: String = ""
    /// 克隆的文字微调：音色跟参考音频走，这段话只调语气 / 语速 / 气息
    @Published var cloneTweak: String = ""
    @Published var cloneName: String = ""
    @Published var analysis: CloneAnalysis?
    @Published var issues: [CloneIssue] = []
    @Published var isAnalyzing = false
    @Published var draftClone: VoiceProfile?
    @Published var isReadingAudio = false

    // 现场录音 + 本地转写
    @Published private(set) var isRecording = false
    @Published private(set) var recordElapsed: Double = 0
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedFromRecording = false

    // 造声
    @Published var designDescription: String = ""
    @Published var designGuidance: Double = AppConfig.defaultGuidanceScale
    @Published var designName: String = ""
    @Published var draftDesign: VoiceProfile?
    @Published var isDesigning = false

    // 试听
    @Published var previewingVoiceID: UUID?
    @Published var alert: AlertPayload?

    let voices: VoiceStore
    let player: AudioPlayerController
    let runtime: SpeechRuntime
    let recorder = ReferenceRecorder()

    private var importedSamples: [Float] = []
    private var importedSampleRate: Double = AppConfig.sampleRate

    init(voices: VoiceStore, player: AudioPlayerController, runtime: SpeechRuntime) {
        self.voices = voices
        self.player = player
        self.runtime = runtime
        self.cloneName = "我的克隆 \(voices.cloneVoices.count + 1)"
        self.designName = "我的造声 \(voices.designVoices.count + 1)"
        recorder.onFinished = { [weak self] url in
            Task { @MainActor in
                self?.finishVoiceMemo(url: url)
            }
        }
    }

    var previewText: String {
        "你好，我是这条声线的试听样本。| 现在，请听一下我的自然度。"
    }

    var isBusy: Bool {
        isAnalyzing || isDesigning || previewingVoiceID != nil || isTranscribing
    }

    // MARK: - 现场录音（克隆）

    func toggleRecording() {
        if isRecording {
            recorder.stop()
        } else {
            player.stop() // 别让播放和录音抢话筒
            recorder.start()
            syncRecorderState()
        }
    }

    private var recorderSyncTask: Task<Void, Never>?

    private func syncRecorderState() {
        isRecording = recorder.isRecording
        recordElapsed = recorder.elapsed
        // 只起一个轮询循环，录音结束后自然退出
        guard isRecording, recorderSyncTask == nil else { return }
        recorderSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { break }
                self.isRecording = self.recorder.isRecording
                self.recordElapsed = self.recorder.elapsed
                if !self.isRecording { break }
            }
            self?.recorderSyncTask = nil
        }
    }

    /// 录完自动接：转写原文 → 提取声纹，全程不需要用户打字
    private func finishVoiceMemo(url: URL?) {
        syncRecorderState()
        guard let url else {
            alert = AlertPayload(
                title: "录音太短",
                message: "克隆至少需要 \(Int(AppConfig.minReferenceSeconds)) 秒的清晰人声，请再录一次。"
            )
            return
        }
        importURL = url
        importFileName = "现场录音 \(TimeFormat.duration(recorder.elapsed))"
        draftClone = nil
        analysis = nil
        issues = []
        transcribedFromRecording = true
        Task { await autoTranscribeAndExtract() }
    }

    /// 录音后的一键链路：本地转写原文 → 提取声纹 → 出草稿 + 试听
    func autoTranscribeAndExtract() async {
        guard let url = importURL, !isTranscribing, !isAnalyzing else { return }
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let text = try await TranscriptionService.transcribe(url: url)
            guard !text.isEmpty else { throw TranscriptionError.empty }
            referenceText = text
        } catch {
            isTranscribing = false
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert = AlertPayload(title: "识别失败", message: "\(message)\n也可以导入音频后手动填写原话。")
            return
        }

        await extractClone()
    }

    // MARK: - 导入

    func importAudio(url: URL) {
        isReadingAudio = true
        defer { isReadingAudio = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        let copyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breeze_import_\(UUID().uuidString).\(ext)")

        do {
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try? FileManager.default.removeItem(at: copyURL)
            }
            try FileManager.default.copyItem(at: url, to: copyURL)
            importURL = copyURL
            importFileName = url.lastPathComponent
            draftClone = nil
            analysis = nil
            issues = []
        } catch {
            alert = AlertPayload(title: "无法读取音频", message: error.localizedDescription)
        }
    }

    // MARK: - 克隆

    func extractClone() async {
        guard let url = importURL else {
            alert = AlertPayload(title: "还没有参考音频", message: "请先导入一段 3~30 秒的 wav / m4a。")
            return
        }
        guard !isAnalyzing else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let result = try WAVFile.read(url: url)
            guard result.samples.count > 0 else { throw TTSError.audioUnreadable("音频为空") }
            importedSamples = result.samples
            importedSampleRate = result.sampleRate

            let analysis = CloneValidator.analyze(
                samples: result.samples,
                sampleRate: result.sampleRate,
                transcript: referenceText
            )
            self.analysis = analysis
            self.issues = analysis.issues

            if let blocking = analysis.issues.first(where: \.isBlocking) {
                draftClone = nil
                alert = AlertPayload(title: blocking.title, message: blocking.message)
                Haptics.warning()
                return
            }

            let signature = VoiceSignatureFactory.makeClone(
                samples: result.samples,
                sampleRate: result.sampleRate,
                transcript: referenceText
            )
            var voice = VoiceProfile(
                name: cloneName.isEmpty ? "克隆声线 \(voices.cloneVoices.count + 1)" : cloneName,
                kind: .clone,
                spk: nil,
                descriptor: "声音克隆 · SNR \(Int(analysis.snr)) dB",
                signature: signature,
                guidanceScale: AppConfig.defaultGuidanceScale,
                speed: AppConfig.defaultSpeed,
                referenceText: referenceText,
                referenceDuration: analysis.duration
            )
            let tweak = cloneTweak.trimmingCharacters(in: .whitespacesAndNewlines)
            voice.tweak = tweak.isEmpty ? nil : tweak
            voice.embeddingFileName = VoiceSignatureFactory.persist(
                signature,
                for: voice.id,
                extra: ["type": "clone", "snr": String(format: "%.1f", analysis.snr)]
            )
            // 参考音频必须在「提取」这一步就落盘：
            // 试听走的是这个草稿声线，引擎要按 referenceFileName 去找音频；
            // 而现场录音的 importURL 在临时目录里，随时会被系统清掉。
            // 之前只有「保存到声线库」才拷贝，所以提取完直接试听必然报
            // 「这条克隆声线缺少参考音频」。
            voice.referenceFileName = persistReferenceAudio(from: url, voiceID: voice.id)
            draftClone = voice
            Haptics.success()
            await preview(voice)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert = AlertPayload(title: "提取失败", message: message)
        }
    }

    /// 把参考音频复制进沙盒固定目录，返回文件名。失败返回 nil（试听会明确报缺少音频）
    @discardableResult
    private func persistReferenceAudio(from source: URL, voiceID: UUID) -> String? {
        AppPaths.ensure(AppPaths.referencesDirectory)
        let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension
        let fileName = "\(voiceID.uuidString).\(ext)"
        let destination = AppPaths.referencesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) { return fileName }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return fileName
        } catch {
            return nil
        }
    }

    @discardableResult
    func saveDraftClone() -> Bool {
        guard var voice = draftClone else {
            alert = AlertPayload(title: "还没有提取声纹", message: "先导入参考音频并点击「提取声纹」。")
            return false
        }
        guard voices.cloneVoices.count < AppConfig.maxCloneVoices else {
            alert = AlertPayload(title: "克隆声线已满", message: "最多保存 \(AppConfig.maxCloneVoices) 条克隆声线，请先删除一条。")
            return false
        }

        voice.name = cloneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? voice.name
            : cloneName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 参考音频入库，便于之后重建 embedding。
        // 提取阶段已经落盘过；这里只补漏（例如用户导入后直接保存、或草稿复制失败）。
        if voice.referenceFileName == nil, let source = importURL {
            voice.referenceFileName = persistReferenceAudio(from: source, voiceID: voice.id)
        }
        guard voice.referenceFileName != nil else {
            alert = AlertPayload(
                title: "保存失败",
                message: "参考音频没能写入沙盒，这条声线之后无法生成语音。请重新导入后再试。"
            )
            return false
        }

        if voices.add(voice) == nil {
            alert = AlertPayload(title: "保存失败", message: "克隆声线数量已达上限。")
            return false
        }
        resetCloneDraft()
        Haptics.success()
        return true
    }

    func resetCloneDraft() {
        draftClone = nil
        analysis = nil
        issues = []
        importedSamples = []
        importURL = nil
        importFileName = ""
        referenceText = ""
        cloneTweak = ""
        transcribedFromRecording = false
        cloneName = "我的克隆 \(voices.cloneVoices.count + 1)"
    }

    // MARK: - 造声

    func createDesign() async {
        let description = designDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            alert = AlertPayload(title: "还没有声音描述", message: "写清楚年龄、性别、音色、沙哑/清亮、气息、口音风格，描述越具体越稳定。")
            return
        }
        guard !isDesigning else { return }

        isDesigning = true
        defer { isDesigning = false }

        let signature = VoiceSignatureFactory.makeDesign(description: description, guidance: designGuidance)
        var voice = VoiceProfile(
            name: designName.isEmpty ? "造声声线 \(voices.designVoices.count + 1)" : designName,
            kind: .design,
            spk: nil,
            descriptor: description,
            signature: signature,
            guidanceScale: designGuidance,
            speed: AppConfig.defaultSpeed
        )
        voice.embeddingFileName = VoiceSignatureFactory.persist(
            signature,
            for: voice.id,
            extra: ["type": "design", "description": description]
        )
        draftDesign = voice
        Haptics.success()
        await preview(voice)
    }

    @discardableResult
    func saveDraftDesign() -> Bool {
        guard var voice = draftDesign else { return false }
        let trimmed = designName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { voice.name = trimmed }
        guard voices.add(voice) != nil else {
            alert = AlertPayload(title: "保存失败", message: "无法写入声线库。")
            return false
        }
        draftDesign = nil
        designDescription = ""
        designName = "我的造声 \(voices.designVoices.count + 1)"
        Haptics.success()
        return true
    }

    // MARK: - 试听

    func preview(_ voice: VoiceProfile) async {
        guard previewingVoiceID == nil else { return }
        previewingVoiceID = voice.id

        let request = TTSRequest(
            text: previewText,
            voice: voice,
            direction: "",
            guidanceScale: voice.guidanceScale,
            speed: 1.0,
            isPreview: true
        )
        do {
            let result = try await runtime.synthesize(request, onProgress: { _ in }, onPartial: { _ in })
            player.load(samples: result.samples, sampleRate: result.sampleRate)
            player.play()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert = AlertPayload(title: "试听失败", message: message)
        }
        previewingVoiceID = nil
    }
}
