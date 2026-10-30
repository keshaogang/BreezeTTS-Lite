//
//  SynthesisViewModel.swift
//  BreezeSpeak
//
//  主界面状态机：文本 / 演绎指令 / 声线 → 生成 → 播放 → 历史。
//

import Foundation
import SwiftUI

struct AlertPayload: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var isWarning: Bool = true
}

/// 生成过程中「引擎线程写、主线程读」的增量状态。
/// 单独成类是为了绕开 MainActor 隔离：采样在引擎线程到达，
/// 如果每次刷新都把它们搬回主线程复制一遍，长音频会退化成 O(n²)。
private final class StreamState: @unchecked Sendable {
    let peaks = IncrementalPeaks()
    private let lock = NSLock()
    private var lastRefresh = Date.distantPast
    private var count = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        peaks.reset()
        count = 0
        lastRefresh = Date.distantPast
    }

    func append(_ chunk: UnsafeBufferPointer<Float>) {
        peaks.append(contentsOf: chunk)
        lock.lock()
        count += chunk.count
        lock.unlock()
    }

    /// 波形刷新节流：最快 8 Hz，再密既看不出来也白占主线程
    func shouldRefresh() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastRefresh) > 0.12 else { return false }
        lastRefresh = now
        return true
    }

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

/// 一次「已发送、正在生成」的轮次，用于在对话流里立刻回显用户消息
struct PendingTurn: Equatable {
    var text: String
    var voiceName: String
    var startedAt: Date = Date()
}

@MainActor
final class SynthesisViewModel: ObservableObject {
    // 输入
    @Published var text: String = ""
    @Published var guidanceScale: Double = AppConfig.defaultGuidanceScale
    @Published var speed: Double = AppConfig.defaultSpeed

    // 输出状态
    @Published private(set) var isGenerating = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var livePeaks: [Float] = []
    @Published private(set) var lastResult: TTSResult?
    @Published private(set) var lastRecord: HistoryRecord?
    @Published private(set) var lastElapsed: Double = 0
    @Published private(set) var generatedAt: Date?
    @Published private(set) var pendingTurn: PendingTurn?
    /// 本次生成开始时预估的总耗时（秒），用来推算剩余时间
    @Published private(set) var plannedSeconds: Double?

    // 弹层
    @Published var showVoiceLibrary = false
    @Published var showModelSheet = false
    @Published var showHistory = false
    @Published var showSettings = false
    @Published var showTuning = false
    @Published var showExportPicker = false
    @Published var exportDocument: WAVDocument?
    @Published var exportFileName = "BreezeSpeak.wav"
    @Published var alert: AlertPayload?
    @Published var toast: String?
    /// 来自小组件 / 快捷指令的「新建朗读」信号。自增即触发一次，
    /// 界面侧监听它把焦点交给输入框，不必额外传状态。
    @Published private(set) var composeToken = 0
    /// 生成结束后是否自动播放
    @Published var autoPlay = true

    /// 从桌面上点「开始朗读」进来时调用：只把焦点交回输入框。
    /// 不碰已有正文——用户可能正写着一半，从桌面点回来不该把草稿清掉。
    func requestCompose() {
        composeToken &+= 1
    }

    /// 声线库要停在哪一页。控制中心 / 快捷指令先写这里，
    /// VoiceSheet 一出现就读走并清空——用一次性信号，而不是长期状态，
    /// 否则用户自己切到「内置」后一点别的入口又会被强行拽回克隆页。
    enum VoiceLabTab: String {
        case builtin
        case clone
        case design
    }

    @Published var requestedVoiceTab: VoiceLabTab?

    func requestVoiceLab(tab: VoiceLabTab) {
        requestedVoiceTab = tab
        showVoiceLibrary = true
    }

    /// 单次解码模式下引擎只会在最后吐一次音频，进度条靠这条计时器推进
    private var progressTicker: Task<Void, Never>?

    private static let submitOnReturnKey = "breeze.submitOnReturn"

    /// 回车即发送：写完敲一下回车就生成，适合外接键盘连续出稿。
    @Published var submitOnReturn: Bool {
        didSet { UserDefaults.standard.set(submitOnReturn, forKey: Self.submitOnReturnKey) }
    }

    private static let releaseModelKey = "breeze.releaseModelAfterRun"
    private static let lockVoiceKey = "breeze.lockVoice"

    /// 是否锁定音色（逐帧贪心采样）。
    /// 默认开启：同一段描述、同一段文字，听起来必须是同一个人。
    /// 关掉就回到模型的默认温度采样，每次都会有些细微差别——适合想「抽卡」的时候。
    @Published var lockVoice: Bool {
        didSet { UserDefaults.standard.set(lockVoice, forKey: Self.lockVoiceKey) }
    }

    /// 生成结束后是否卸载权重。
    /// 开启后每次生成收尾就把几百 MB 到 3 GB 还给系统（就是「生成完不占内存」），
    /// 代价是下次生成要重新加载：真机 mmap 热读约 3 秒，首次安装冷读约 17 秒。
    @Published var releaseModelAfterRun: Bool {
        didSet { UserDefaults.standard.set(releaseModelAfterRun, forKey: Self.releaseModelKey) }
    }

    // 依赖
    let voices: VoiceStore
    let model: ModelManager
    let memory: MemoryMonitor
    let history: HistoryStore
    let player: AudioPlayerController
    let runtime: SpeechRuntime

    private var task: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    /// 本次生成的增量波形状态（跨线程，内部自带锁）
    private let stream = StreamState()

    init(voices: VoiceStore, model: ModelManager, memory: MemoryMonitor, history: HistoryStore, player: AudioPlayerController, runtime: SpeechRuntime) {
        self.voices = voices
        self.model = model
        self.memory = memory
        self.history = history
        self.player = player
        self.runtime = runtime
        self.guidanceScale = voices.selectedVoice.guidanceScale
        self.speed = AppConfig.defaultSpeed
        // 在 init 里赋值不会触发 didSet，正好避免回写一次
        self.releaseModelAfterRun = UserDefaults.standard.bool(forKey: Self.releaseModelKey)
        // 没存过就按默认开启（锁定音色）
        self.lockVoice = UserDefaults.standard.object(forKey: Self.lockVoiceKey) as? Bool ?? true
        self.submitOnReturn = UserDefaults.standard.bool(forKey: Self.submitOnReturnKey)
    }

    // MARK: - 派生

    var characterCount: Int { text.count }

    var effectiveVoice: VoiceProfile {
        voices.selectedVoice
    }

    var peaks: [Float] {
        if !livePeaks.isEmpty { return livePeaks }
        return player.peaks
    }

    var canGenerate: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var engineLabel: String { runtime.engineLabel }
    var engineNote: String { runtime.note }
    var isNeural: Bool { runtime.isNeural }

    // MARK: - 耗时估算

    /// 预计还要多久：按实时率折算，权重没加载时含冷启动
    var estimatedSeconds: Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNeural, !trimmed.isEmpty else { return nil }
        return GenerationEstimator.estimate(
            text: trimmed,
            tierID: model.selectedTier.id,
            modelLoaded: BreezeEngineCore.shared.isLoaded
        )
    }

    /// 页脚左侧的「约 X 秒」
    var estimateLabel: String? {
        guard !isGenerating, let seconds = estimatedSeconds else { return nil }
        return GenerationEstimator.format(seconds)
    }

    /// 生成中按进度推算的剩余时间
    var remainingLabel: String? {
        guard isGenerating, let planned = plannedSeconds else { return nil }
        let remaining = planned * (1 - min(1, max(0, progress)))
        guard remaining > 1 else { return nil }
        return GenerationEstimator.format(remaining)
    }

    // MARK: - 生成

    func generate() {
        guard task == nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = AlertPayload(title: "还没有文本", message: "先输入要朗读的内容，或点一个快捷模板。")
            return
        }

        let voice = effectiveVoice
        let request = TTSRequest(
            text: trimmed,
            voice: voice,
            guidanceScale: guidanceScale,
            speed: speed,
            sampling: lockVoice ? .locked : .free
        )

        runtime.refresh()
        if runtime.isNeural {
            // 这里刻意不做「预判拦截」。
            //
            // os_proc_available_memory() 衡量的是「离被系统杀掉还有多远」，而 mmap 进来的
            // 权重本身就占着这份配额：Q4_K 常驻后它通常只剩几百 MB。拿它去判断
            // 「还能不能生成」，等于把已经在内存里的权重又重复计了一遍 —— 这就是
            // 「生成完一次，第二次必然报内存不足」的真正原因，阈值怎么调都治不好。
            //
            // 真正的保护留在两头：
            //   1) 档位明显超过本机内存时给一条非阻塞提示（下面这条 toast）；
            //   2) 运行中收到系统内存警告就释放权重（AppEnvironment.handleMemoryWarning）。
            let peak = Double(model.selectedTier.peakBytes)
            let physical = Double(ProcessInfo.processInfo.physicalMemory)
            if !runtime.isEngineLoaded, peak > physical * 0.45 {
                showToast("\(model.selectedTier.shortName) 档峰值约 \(TimeFormat.bytes(Int64(peak)))，本机内存 \(TimeFormat.bytes(Int64(physical)))，余量偏紧；若生成被系统中断，请到「模型」换更小的档")
            }
        }

        isGenerating = true
        progress = 0
        livePeaks = []
        stream.reset()
        lastResult = nil
        plannedSeconds = estimatedSeconds
        memory.resetPeak()
        memory.start()

        // 这条声线还没有音色锚点：第一次会先跑一段固定文稿把音色钉住，多花几秒
        if lockVoice, voice.kind != .clone, !VoiceAnchor.exists(for: voice) {
            showToast("首次使用「\(voice.displayName)」：正在固定音色，会多花几秒")
        }

        // 书写面形态：文本保留在原处，方便改完直接重新生成
        pendingTurn = PendingTurn(text: trimmed, voiceName: voice.displayName)

        startProgressTicker(planned: plannedSeconds)

        let started = Date()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.runtime.synthesize(
                    request,
                    onProgress: { value in
                        Task { @MainActor in
                            // 整段一次解码时引擎只在结尾回 1.0，中途靠计时器推进；
                            // 这里只允许真实进度把指针往前推，不能被 0.02 打回原点。
                            self.progress = max(self.progress, value)
                        }
                    },
                    onPartial: { partial in
                        Task { @MainActor in self.consume(partial) }
                    },
                    // 引擎线程增量回传「本次新增采样」，波形走增量累积，
                    // 不再每次刷新复制整个音频数组
                    onChunk: { chunk in
                        self.stream.append(chunk)
                        guard self.stream.shouldRefresh() else { return }
                        Task { @MainActor in self.refreshLivePeaks() }
                    }
                )
                if Task.isCancelled { throw TTSError.cancelled }
                self.finish(result: result, request: request, elapsed: Date().timeIntervalSince(started))
            } catch {
                self.handleFailure(error)
            }
            self.task = nil
            self.isGenerating = false
            self.memory.sample()
        }
    }

    /// 重新给当前声线打锚点：清掉锚点与音频缓存，下次生成会重新采一段声音钉住。
    /// 第一次钉下来的音色不一定是最合适的那一次，给用户一个重抽的机会。
    func reanchorCurrentVoice() {
        let voice = effectiveVoice
        guard voice.kind != .clone else { return }
        VoiceAnchor.invalidate(voice.id)
        AudioCache.clear()
        showToast("已清掉「\(voice.displayName)」的音色锚点，下次生成会重新采样固定")
    }

    func cancel() {
        progressTicker?.cancel()
        progressTicker = nil
        task?.cancel()
        runtime.cancelCurrent()
        task = nil
        isGenerating = false
        pendingTurn = nil
        plannedSeconds = nil
        toast = "已取消生成"
    }

    /// 生成中按预估耗时间推进进度条。
    ///
    /// 引擎现在整段一次解码（见 AppConfig.decodeChunkFrames），中途没有音频回调，
    /// 进度只能靠时间推：先用渐近曲线爬到 94%，真实结果到达时直接置 1。
    /// 不做这条的话，长句生成期间界面会一动不动十几秒，看着像卡死。
    private func startProgressTicker(planned: Double?) {
        progressTicker?.cancel()
        let budget = max(planned ?? 6, 1.5)
        let begin = Date()
        progressTicker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 140_000_000)
                guard let self, self.isGenerating else { return }
                let elapsed = Date().timeIntervalSince(begin)
                // 0.62 的时间常数：前半程走得快，后半程慢慢爬到 94%，
                // 既不让人以为卡住，也不会早早停在 99% 等真实进度。
                let guess = 0.94 * (1 - exp(-elapsed / (budget * 0.62)))
                if guess > self.progress {
                    self.progress = min(0.94, guess)
                }
            }
        }
    }

    /// 生成中刷新：波形取增量累积器的快照（O(1)），不再重扫整个音频
    private func refreshLivePeaks() {
        livePeaks = stream.peaks.snapshot(bars: 120)
        memory.mlxActive = runtime.isNeural ? DeviceMemory.footprint() : 0
    }

    /// 生成结束（或兜底引擎）拿到完整结果时用全量波形
    private func consume(_ partial: TTSResult) {
        livePeaks = AudioAnalysis.peaks(from: partial.samples, count: 120)
        memory.mlxActive = runtime.isNeural ? DeviceMemory.footprint() : 0
    }

    private func finish(result: TTSResult, request: TTSRequest, elapsed: Double) {
        progressTicker?.cancel()
        progressTicker = nil
        lastResult = result
        lastElapsed = elapsed
        generatedAt = Date()
        livePeaks = AudioAnalysis.peaks(from: result.samples, count: 140)
        progress = 1

        player.load(samples: result.samples, sampleRate: result.sampleRate)

        if let record = history.add(
            text: request.text,
            voice: request.voice,
            direction: request.direction,
            guidance: request.guidanceScale,
            speed: request.speed,
            result: result,
            engineName: runtime.engineLabel
        ) {
            lastRecord = record
        }

        memory.sample()
        pendingTurn = nil
        plannedSeconds = nil
        Haptics.success()
        if autoPlay { player.play() }
        showToast(String(format: "生成完成 · %.2f 秒音频 · 耗时 %.1f 秒", result.duration, elapsed))

        // 「生成后释放模型」：把权重还给系统，下次生成再重新加载。
        // 默认关闭——常驻权重才能让连续生成不用每次等 3 秒加载。
        if releaseModelAfterRun {
            runtime.unloadAll()
        }
    }

    private func handleFailure(_ error: Error) {
        progressTicker?.cancel()
        progressTicker = nil
        pendingTurn = nil
        plannedSeconds = nil
        if case TTSError.cancelled = error {
            toast = "已取消生成"
            return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        // 落盘留证：失败弹窗关掉就没了，事后无法复盘是内存不足还是引擎报错
        PerformanceLog.recordFailure(
            message,
            characters: text.count,
            detail: String(format: "引擎 %@ · 权重 %@ · 进程 %.0f MB",
                           runtime.engineLabel,
                           model.selectedTier.shortName,
                           Double(DeviceMemory.footprint()) / 1_048_576)
        )
        alert = AlertPayload(title: "生成失败", message: message)
        Haptics.warning()
    }

    // MARK: - 播放

    func playPause() {
        guard lastResult != nil || !player.peaks.isEmpty else {
            alert = AlertPayload(title: "还没有音频", message: "先点击「生成语音」，或从右侧历史记录中选一条重听。")
            return
        }
        player.toggle()
    }

    func play(record: HistoryRecord) {
        player.loadFile(at: record.fileURL)
        player.play()
        lastRecord = record
        livePeaks = record.peaks
    }

    // MARK: - 导出

    func exportWAV() {
        if let result = lastResult {
            prepareExport(samples: result.samples, sampleRate: result.sampleRate, nameBase: "BreezeSpeak")
        } else if let record = lastRecord, FileManager.default.fileExists(atPath: record.fileURL.path) {
            exportFile(at: record.fileURL)
        } else {
            alert = AlertPayload(title: "没有可导出的音频", message: "先生成一段语音。")
        }
    }

    func exportFile(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            alert = AlertPayload(title: "导出失败", message: "音频文件不存在或不可读。")
            return
        }
        exportDocument = WAVDocument(data: data)
        exportFileName = url.lastPathComponent
        showExportPicker = true
    }

    private func prepareExport(samples: [Float], sampleRate: Double, nameBase: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        exportFileName = "\(nameBase)_\(formatter.string(from: Date())).wav"
        exportDocument = WAVDocument(data: WAVFile.data(samples: samples, sampleRate: sampleRate))
        showExportPicker = true
    }

    /// 同时写一份到「文件」App 可见目录，方便隔空投送
    @discardableResult
    func saveToDocumentsFolder() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        let directory = AppPaths.exportDirectory

        if let result = lastResult {
            let url = directory.appendingPathComponent("BreezeSpeak_\(stamp).wav")
            guard WAVFile.write(samples: result.samples, sampleRate: result.sampleRate, to: url) else {
                alert = AlertPayload(title: "保存失败", message: "写入「文件」App 目录时出错。")
                return nil
            }
            showToast("已保存到「文件」App / BreezeSpeak")
            return url
        }

        if let record = lastRecord, FileManager.default.fileExists(atPath: record.fileURL.path) {
            let url = directory.appendingPathComponent("BreezeSpeak_\(stamp).wav")
            try? FileManager.default.removeItem(at: url)
            do {
                try FileManager.default.copyItem(at: record.fileURL, to: url)
                showToast("已保存到「文件」App / BreezeSpeak")
                return url
            } catch {
                alert = AlertPayload(title: "保存失败", message: error.localizedDescription)
                return nil
            }
        }

        alert = AlertPayload(title: "没有可保存的音频", message: "先生成一段语音。")
        return nil
    }

    // MARK: - 声线 / 模板

    func applyVoice(_ voice: VoiceProfile) {
        voices.select(voice.id)
        guidanceScale = voice.guidanceScale
        Haptics.light()
    }

    func applyTemplate(_ template: PromptTemplate) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = template.text
        } else {
            text += (text.hasSuffix("\n") ? "" : "\n") + template.text
        }
        Haptics.light()
    }

    func reuseHistory(_ record: HistoryRecord) {
        text = record.text
        guidanceScale = record.guidance
        speed = record.speed
        if let voice = voices.voice(id: record.voiceID) {
            voices.select(voice.id)
        } else if let spk = record.spk, let voice = voices.voice(spk: spk) {
            voices.select(voice.id)
        }
        generate()
    }

    // MARK: - 提示

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func clearText() {
        text = ""
    }
}
