import AppKit
import Combine
import Foundation

/// Central coordinator: model lifecycle, generation runs, playback and export.
/// Everything user-visible funnels through here so the views stay declarative.
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingModel
        case generating
        case done
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .loadingModel, .generating: return true
            default: return false
            }
        }
    }

    let settings: AppSettings
    let history: HistoryStore
    let voices: VoiceStore
    let player: AudioPlayer
    /// Transport for finished audio (play / pause / scrub). The streaming player
    /// above only covers the live run.
    let playback: PlaybackService
    let downloader: ModelDownloader
    let recorder: VoiceRecorder
    /// Predicts run duration; also collects what really happened.
    let estimator: GenerationEstimator

    @Published var text = ""
    @Published var phase: Phase = .idle
    @Published var statusLine = ""
    @Published var generatedSamples: [Float] = []
    @Published var generationSeconds: Double = 0
    @Published var audioSeconds: Double = 0
    /// Live percentage + countdown for the run in flight.
    @Published var runProgress: RunProgress?
    @Published var activeModelPath: String?
    @Published var selectedVoiceID: UUID?
    /// Drives which root view is shown; false once the guided setup is done.
    @Published var needsOnboarding: Bool
    @Published var lastExportedURL: URL?

    private var progressTimer: Timer?
    private var generationStarted: Date?
    private var cancellables: Set<AnyCancellable> = []
    /// Snapshot of the estimate taken when the run started.
    private var runForecast: GenerationForecast?
    private var firstChunkAt: Double?
    private var runLoadSeconds: Double = 0

    init(settings: AppSettings = AppSettings(),
         history: HistoryStore = HistoryStore(),
         voices: VoiceStore = VoiceStore(),
         player: AudioPlayer = AudioPlayer(),
         playback: PlaybackService = PlaybackService(),
         downloader: ModelDownloader = ModelDownloader(),
         recorder: VoiceRecorder = VoiceRecorder(),
         estimator: GenerationEstimator = .shared) {
        self.settings = settings
        self.history = history
        self.voices = voices
        self.player = player
        self.playback = playback
        self.downloader = downloader
        self.recorder = recorder
        self.estimator = estimator
        self.needsOnboarding = !settings.onboarded

        Paths.ensureDirectories()

        // Views observe the model, so transport changes have to be re-published.
        playback.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // The toolbar label follows `settings.instruction`, so style changes made
        // in any sheet have to refresh the main window too.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Strategy / override changes take effect immediately, as the spec requires.
        settings.$strategy
            .dropFirst()
            .sink { [weak self] _ in self?.modelSelectionChanged() }
            .store(in: &cancellables)

        settings.$overrideTierID
            .dropFirst()
            .sink { [weak self] _ in self?.modelSelectionChanged() }
            .store(in: &cancellables)

        if RenderMode.isPreview {
            text = "欢迎使用 Breeze TTS。这是一个完全本地运行的语音合成工具：模型在你自己的 Mac 上推理，文本不会离开这台机器。\n\n把任意中英文段落粘到左边，点「生成语音」，几秒后就能听到结果，也可以直接导出 WAV 交剪辑软件使用。"
            statusLine = "本地引擎就绪 · Metal 加速"
            // Gives the snapshot harness a finished clip so the transport renders.
            audioSeconds = 9.4
            generatedSamples = [0]
            playback.seedPreview(duration: 9.4, at: 3.2)
        }
    }

    // MARK: - Derived state

    var activeSpec: ModelSpec { settings.resolvedSpec }

    var activeSpecInstalled: Bool { activeSpec.installed }

    var selectedVoice: VoiceMeta? {
        guard let selectedVoiceID else { return nil }
        return voices.voices.first { $0.id == selectedVoiceID }
    }

    // MARK: - Voice style

    /// The preset currently in effect, or nil when the wording is hand-written.
    var activeStyle: VoiceStyle? {
        VoiceStyles.match(instruction: settings.instruction)
    }

    /// The saved text voice whose wording is currently in effect. Matching is
    /// derived from the instruction itself, so no extra selection state exists
    /// to fall out of sync.
    var activeTextVoice: VoiceMeta? {
        let current = settings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return nil }
        return voices.voices.first {
            ($0.instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(current) == .orderedSame
        }
    }

    /// What the toolbar button shows: an explicit clone wins, otherwise the style.
    var voiceLabel: String {
        if let selectedVoice { return selectedVoice.name }
        if let style = activeStyle {
            return style.id == VoiceStyles.neutral.id ? "音色" : style.name
        }
        if let textVoice = activeTextVoice { return textVoice.name }
        // 空指令 = 中性默认（克隆/文字音色都不选时的单选空位）。
        let current = settings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? "中性自然" : "自定义"
    }

    /// Best guess for the text in the editor, used for the toolbar hint dot.
    var suggestedStyle: VoiceAdvisor.Pick? {
        VoiceAdvisor.recommend(for: text, limit: 1).first
    }

    /// A style never clears a cloned voice: the clone decides *who* speaks, the
    /// style decides *how*. Hand-written wording is kept aside so the menu can
    /// hand it back.
    func applyStyle(_ style: VoiceStyle) {
        let current = settings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if VoiceStyles.match(instruction: current) == nil,
           !current.isEmpty,
           current.caseInsensitiveCompare(style.instruction) != .orderedSame {
            settings.instructionBackup = current
        }
        settings.instruction = style.instruction
        statusLine = style.id == VoiceStyles.neutral.id ? "声线：中性自然" : "声线：\(style.name)"
    }

    /// Applies a saved text voice: its wording becomes the instruction. 单选模式：
    /// 文字音色与克隆音色互斥，选一个就清掉另一个。
    func applyTextVoice(_ voice: VoiceMeta) {
        let wording = (voice.instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let current = settings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, current.caseInsensitiveCompare(wording) != .orderedSame {
            settings.instructionBackup = settings.instruction
        }
        settings.instruction = voice.instruction ?? ""
        selectedVoiceID = nil
        statusLine = "声线：\(voice.name)"
    }

    /// 选中克隆音色：参考音频决定音色，音色自带的文字辅助描述叠加为指令
    /// （语气/语速/情绪），保持单选。
    func selectCloneVoice(_ voice: VoiceMeta) {
        let current = settings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let wording = (voice.instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, current.caseInsensitiveCompare(wording) != .orderedSame {
            settings.instructionBackup = settings.instruction
        }
        settings.instruction = voice.instruction ?? ""
        selectedVoiceID = voice.id
        statusLine = "声线：\(voice.name)"
    }

    /// 回到中性默认：无克隆、无文字声线。
    func resetToNeutralVoice() {
        let current = settings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            settings.instructionBackup = settings.instruction
        }
        settings.instruction = ""
        selectedVoiceID = nil
        statusLine = "声线：中性自然"
    }

    /// Saves a text-described voice. Empty wording is meaningless, so it is
    /// rejected at the store boundary.
    @discardableResult
    func saveTextVoice(name: String, instruction: String) -> VoiceMeta? {
        let wording = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !wording.isEmpty else { return nil }
        return voices.addTextVoice(name: title, instruction: wording)
    }

    /// Puts the hand-written instruction back, if a preset replaced it.
    var canRestoreInstruction: Bool {
        guard let backup = settings.instructionBackup, !backup.isEmpty else { return false }
        return backup.caseInsensitiveCompare(settings.instruction) != .orderedSame
    }

    func restoreCustomInstruction() {
        guard let backup = settings.instructionBackup, !backup.isEmpty else { return }
        settings.instruction = backup
        statusLine = "已恢复自定义指令"
    }

    var modelFileURL: URL? {
        if let custom = settings.customModelPath, Paths.exists(URL(fileURLWithPath: custom)) {
            return URL(fileURLWithPath: custom)
        }
        // Catalogue entries must match their exact byte count: a half finished
        // download would fail inside breeze_init with a confusing error.
        if activeSpec.installed { return activeSpec.fileURL }
        // Fall back to any complete gguf so a hand-imported file still works.
        return ModelCatalog.installedFiles().first { url in
            if let spec = ModelCatalog.spec(fileName: url.lastPathComponent) {
                return spec.installed
            }
            return Paths.size(of: url) > 200_000_000
        }
    }

    var modelReady: Bool { modelFileURL != nil }

    var modelLabel: String {
        if let path = modelFileURL, let spec = ModelCatalog.spec(fileName: path.lastPathComponent) {
            return spec.displayName
        }
        return modelFileURL?.lastPathComponent ?? "未选择模型"
    }

    var isModelLoaded: Bool {
        guard let activeModelPath else { return false }
        return activeModelPath == modelFileURL?.path
    }

    var charCount: Int { text.count }

    var estimatedFrames: Int { max(1, Int(Double(charCount) * 1.6)) }

    // MARK: - Duration estimate

    /// Catalogue id of the weights in use, so calibration is kept per file.
    private var estimateModelID: String {
        guard let url = modelFileURL,
              let spec = ModelCatalog.spec(fileName: url.lastPathComponent) else { return "custom" }
        return spec.id
    }

    private var estimateModelBytes: Int64 {
        guard let url = modelFileURL else { return activeSpec.bytes }
        if let spec = ModelCatalog.spec(fileName: url.lastPathComponent) { return spec.bytes }
        return Paths.size(of: url)
    }

    /// Calibration samples are keyed per weight file AND per playback mode: a
    /// single-flush run is ~40% faster, so mixing the two would corrupt the RTF.
    private var calibrationModelID: String {
        estimateModelID + (settings.streamPlayback ? "" : "-ns")
    }

    /// What the footer shows while typing: clip length plus wall-clock estimate.
    var forecast: GenerationForecast? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return estimator.forecast(for: trimmed,
                                  modelID: calibrationModelID,
                                  modelBytes: estimateModelBytes,
                                  modelLoaded: isModelLoaded,
                                  refAudioSeconds: selectedVoice?.durationSeconds ?? 0,
                                  streaming: settings.streamPlayback)
    }

    // MARK: - First run

    func completeOnboarding() {
        settings.onboarded = true
        needsOnboarding = false
        statusLine = ""
        if let url = modelFileURL, !isModelLoaded {
            loadModel(at: url)
        }
    }

    func restartOnboarding() {
        needsOnboarding = true
    }

    // MARK: - Bootstrapping

    /// "模型已就绪 · 24000 Hz · Metal 加速" — the backend name tells a silent
    /// CPU fallback apart from a genuinely loaded GPU path.
    static var readyStatusLine: String {
        let backend = SpeechEngine.shared.backendName
        return "模型已就绪 · \(Int(SpeechEngine.shared.sampleRate)) Hz"
            + (backend.isEmpty ? "" : " · \(backend) 加速")
    }

    /// Called from the main view's `.task`. Loads whatever model is already on disk.
    func bootstrap() {
        Paths.ensureDirectories()
        // The snapshot harness seeds its own state and must not load weights.
        if RenderMode.isPreview { return }
        player.configure(sampleRate: SpeechEngine.shared.sampleRate)
        recorder.configure(sampleRate: SpeechEngine.shared.sampleRate)

        if let url = modelFileURL {
            statusLine = "正在加载模型…"
            loadModel(at: url)
        } else {
            phase = .idle
            statusLine = "尚未安装模型，先从「模型」面板下载一档权重"
        }
    }

    func loadModel(at url: URL) {
        guard phase != .loadingModel else { return }
        // The model IS the active one already: nothing to do.
        if isModelLoaded {
            phase = .idle
            statusLine = Self.readyStatusLine
            return
        }

        phase = .loadingModel
        statusLine = "正在加载 \(url.lastPathComponent)…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            SpeechEngine.shared.load(path: url.path, useGPU: self.settings.useGPU) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.activeModelPath = url.path
                    self.player.configure(sampleRate: SpeechEngine.shared.sampleRate)
                    self.recorder.configure(sampleRate: SpeechEngine.shared.sampleRate)
                    self.phase = .idle
                    self.statusLine = Self.readyStatusLine
                case .failure(let error):
                    self.phase = .failed(error.localizedDescription)
                    self.statusLine = "模型加载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func modelSelectionChanged() {
        // Switching strategy swaps the weight file; do it lazily so we never hold two
        // multi-gigabyte contexts at once.
        SpeechEngine.shared.unload()
        activeModelPath = nil
        if let url = modelFileURL {
            loadModel(at: url)
        } else {
            phase = .idle
            statusLine = "当前档位未下载：\(activeSpec.displayName)"
        }
    }

    // MARK: - Generation

    func generate() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusLine = "先输入要合成的文本"
            return
        }
        guard let url = modelFileURL else {
            phase = .failed("没有可用的模型文件")
            statusLine = "请先下载模型"
            return
        }
        if phase == .generating { return }

        // Freeze the estimate now: loading weights must not change the promise
        // the user is looking at.
        let plan = forecast ?? estimator.forecast(for: trimmed,
                                                  modelID: calibrationModelID,
                                                  modelBytes: estimateModelBytes,
                                                  modelLoaded: isModelLoaded,
                                                  refAudioSeconds: selectedVoice?.durationSeconds ?? 0,
                                                  streaming: settings.streamPlayback)
        runForecast = nil
        runProgress = nil
        runLoadSeconds = 0

        let start: () -> Void = { [weak self] in
            self?.runGeneration(text: trimmed, plan: plan)
        }

        if isModelLoaded {
            start()
        } else {
            statusLine = "加载模型后开始合成…"
            let loadBegan = Date()
            SpeechEngine.shared.load(path: url.path, useGPU: settings.useGPU) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.runLoadSeconds = Date().timeIntervalSince(loadBegan)
                    self.activeModelPath = url.path
                    self.player.configure(sampleRate: SpeechEngine.shared.sampleRate)
                    start()
                case .failure(let error):
                    self.phase = .failed(error.localizedDescription)
                    self.statusLine = "模型加载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runGeneration(text trimmed: String, plan: GenerationForecast) {
        phase = .generating
        generationSeconds = 0
        audioSeconds = 0
        generatedSamples.removeAll(keepingCapacity: true)
        playback.unload()
        statusLine = "合成中…"
        generationStarted = Date()
        firstChunkAt = nil
        // The weights are in memory by now, so only the streaming part is left.
        var livePlan = plan
        livePlan.loadSeconds = 0
        runForecast = livePlan
        runProgress = RunProgress(fraction: 0.02,
                                  remainingSeconds: max(1, livePlan.computeSeconds))
        startProgressTimer()

        let params = settings.genParams()
        var refAudio: [Float]?
        var refText: String?
        if let voice = selectedVoice {
            if let loaded = ExportService.readSamples(at: voice.url) {
                refAudio = ExportService.resample(loaded.samples,
                                                  from: loaded.sampleRate,
                                                  to: SpeechEngine.shared.sampleRate)
                refText = voice.refText
            }
        }

        // Stream playback is opt-in: off (default) the whole clip is decoded in
        // one vocoder flush — measurably faster — and plays when it is done.
        let streaming = settings.streamPlayback
        if streaming {
            player.begin()
        }

        let rate = SpeechEngine.shared.sampleRate
        SpeechEngine.shared.generate(text: trimmed,
                                     params: params,
                                     refAudio: refAudio,
                                     refText: refText,
                                     streaming: streaming,
                                     onChunk: { [weak self] chunk in
            guard let self else { return }
            if self.firstChunkAt == nil {
                self.firstChunkAt = Date().timeIntervalSince(self.generationStarted ?? Date())
            }
            self.generatedSamples.append(contentsOf: chunk)
            self.audioSeconds = Double(self.generatedSamples.count) / rate
            if streaming {
                self.player.enqueue(chunk)
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            let compute = Date().timeIntervalSince(self.generationStarted ?? Date())
            self.generationSeconds = compute
            self.stopProgressTimer()
            self.runProgress = nil
            self.player.finish()
            switch result {
            case .success(let samples):
                self.generatedSamples = samples
                self.audioSeconds = Double(samples.count) / rate
                self.phase = .done
                if samples.isEmpty {
                    self.playback.unload()
                    self.statusLine = "生成结束，但没有音频输出"
                } else {
                    // Teach the estimator what this machine really did.
                    self.estimator.record(modelID: self.calibrationModelID,
                                          text: trimmed,
                                          audioSeconds: self.audioSeconds,
                                          computeSeconds: compute,
                                          firstChunkSeconds: self.firstChunkAt ?? 0,
                                          loadSeconds: self.runLoadSeconds,
                                          streaming: streaming)
                    let saved = self.finishRun(text: trimmed, params: params, computeSeconds: compute)
                    self.attachPlayback(savedURL: saved)
                    if !streaming {
                        self.playback.play()
                    }
                }
            case .failure(let error):
                self.phase = .failed(error.localizedDescription)
                self.statusLine = "生成失败：\(error.localizedDescription)"
            }
        })
    }

    @discardableResult
    private func finishRun(text trimmed: String, params: GenParams, computeSeconds: Double) -> URL? {
        let name = ExportService.suggestedFileName(for: trimmed)
        let folder = settings.exportFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        var savedPath: String?
        var savedURL: URL?
        do {
            try ExportService.writeWAV(samples: generatedSamples,
                                       sampleRate: SpeechEngine.shared.sampleRate,
                                       to: url)
            savedPath = url.path
            savedURL = url
            lastExportedURL = url
        } catch {
            NSLog("BreezeTTS: export failed \(error.localizedDescription)")
        }

        statusLine = String(format: "完成 · 音频 %.1fs · 用时 %.1fs",
                            audioSeconds, generationSeconds)

        history.add(HistoryItem(text: trimmed,
                                instruction: params.instruction,
                                modelID: settings.resolvedSpec.id,
                                voiceName: selectedVoice?.name,
                                durationSeconds: audioSeconds,
                                wavPath: savedPath,
                                seed: params.seed,
                                computeSeconds: computeSeconds))
        return savedURL
    }

    /// Points the transport at the clip that was just produced.
    private func attachPlayback(savedURL: URL?) {
        guard !generatedSamples.isEmpty else {
            playback.unload()
            return
        }
        if let savedURL, playback.load(url: savedURL) { return }

        // Export failed: encode once into the cache so ⏯ still works.
        Paths.ensureDirectories()
        let scratch = Paths.cache.appendingPathComponent("last-generation.wav")
        if (try? ExportService.writeWAV(samples: generatedSamples,
                                        sampleRate: SpeechEngine.shared.sampleRate,
                                        to: scratch)) != nil {
            playback.load(url: scratch)
        }
    }

    func stop() {
        SpeechEngine.shared.cancel()
        player.stop()
        if playback.isPlaying { playback.pause() }
        stopProgressTimer()
        runProgress = nil
        phase = .done
        statusLine = "已停止"
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let started = self.generationStarted else { return }
            let elapsed = Date().timeIntervalSince(started)
            self.generationSeconds = elapsed
            if let plan = self.runForecast {
                self.runProgress = self.estimator.progress(forecast: plan,
                                                           elapsed: elapsed,
                                                           producedAudio: self.audioSeconds)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Playback / export

    /// Play / pause the finished clip. The streaming engine is silenced first so
    /// a lingering tail can never overlap with the file.
    func togglePlayback() {
        guard playback.hasAudio else { return }
        if playback.isPlaying {
            playback.pause()
        } else {
            player.stop()
            playback.play()
        }
    }

    func seekPlayback(to progress: Double) {
        playback.seek(toProgress: progress)
    }

    func playHistory(_ item: HistoryItem) {
        guard let url = item.url else { return }
        if playback.currentURL == url {
            togglePlayback()
            return
        }
        player.stop()
        playback.play(url: url)
    }

    func exportLast() {
        guard !generatedSamples.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = ExportService.suggestedFileName(for: text)
        panel.directoryURL = settings.exportFolder
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ExportService.writeWAV(samples: generatedSamples,
                                           sampleRate: SpeechEngine.shared.sampleRate,
                                           to: url)
                lastExportedURL = url
                statusLine = "已导出到 \(url.lastPathComponent)"
            } catch {
                statusLine = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Models

    func download(_ spec: ModelSpec) {
        downloader.start(spec)
    }

    func cancelDownload(_ spec: ModelSpec) {
        downloader.cancel(spec)
    }

    func deleteModel(_ spec: ModelSpec) {
        if isModelLoaded, activeModelPath == spec.fileURL.path {
            SpeechEngine.shared.unload()
            activeModelPath = nil
            phase = .idle
        }
        downloader.deleteFile(spec)
    }

    func selectTier(_ id: String?) {
        settings.overrideTierID = id
    }

    /// Calls come from `.fileImporter` inside the sheets — never open an
    /// `NSOpenPanel` modally there, the sheet's own modal session swallows it.
    func importModel(from url: URL) {
        Paths.ensureDirectories()
        let destination = Paths.models.appendingPathComponent(url.lastPathComponent)
        do {
            if Paths.exists(destination) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: url, to: destination)
            settings.customModelPath = destination.path
            statusLine = "已导入 \(destination.lastPathComponent)"
            SpeechEngine.shared.unload()
            activeModelPath = nil
            loadModel(at: destination)
        } catch {
            statusLine = "导入失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Voice cloning

    func saveRecordedVoice(name: String, refText: String, instruction: String = "") {
        let samples = recorder.stop()
        guard samples.count > 2_000 else {
            statusLine = "录音太短，至少说一句完整的话"
            return
        }
        do {
            let meta = try voices.add(name: name.isEmpty ? "我的音色" : name,
                                      samples: samples,
                                      sampleRate: SpeechEngine.shared.sampleRate,
                                      refText: refText,
                                      instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines))
            selectedVoiceID = meta.id
            // 参考音频为主，文字辅助描述（如有）叠加为指令。
            settings.instruction = meta.instruction ?? ""
            statusLine = "已保存音色「\(meta.name)」"
            recorder.discard()
        } catch {
            statusLine = "保存音色失败：\(error.localizedDescription)"
        }
    }

    /// Loads an existing clip as the pending take, so the recorder sheet can
    /// review it, name it and fill in the transcript before saving.
    @discardableResult
    func stageReferenceClip(from url: URL) -> Bool {
        guard let loaded = ExportService.readSamples(at: url) else {
            statusLine = "无法读取该音频文件：\(url.lastPathComponent)"
            return false
        }
        recorder.stage(samples: loaded.samples, sampleRate: loaded.sampleRate)
        guard recorder.hasTake else {
            statusLine = "这个文件里没有可用音频"
            return false
        }
        statusLine = "已载入 \(url.lastPathComponent)，填好名称和逐字稿再保存"
        return true
    }

    /// Saves an existing audio file as a reference clip straight away.
    @discardableResult
    func importReferenceVoice(from url: URL, name: String, refText: String) -> Bool {
        guard let loaded = ExportService.readSamples(at: url) else {
            statusLine = "无法读取该音频文件：\(url.lastPathComponent)"
            return false
        }
        let resampled = ExportService.resample(loaded.samples,
                                               from: loaded.sampleRate,
                                               to: SpeechEngine.shared.sampleRate)
        guard resampled.count > 2_000 else {
            statusLine = "这段音频太短，至少 5 秒效果才好"
            return false
        }
        do {
            let meta = try voices.add(name: name.isEmpty ? url.deletingPathExtension().lastPathComponent : name,
                                      samples: resampled,
                                      sampleRate: SpeechEngine.shared.sampleRate,
                                      refText: refText)
            selectedVoiceID = meta.id
            statusLine = refText.isEmpty
                ? "已导入「\(meta.name)」，但没填参考文本，克隆效果会不稳"
                : "已导入参考音色「\(meta.name)」"
            return true
        } catch {
            statusLine = "导入失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearSelection() {
        selectedVoiceID = nil
    }
}
