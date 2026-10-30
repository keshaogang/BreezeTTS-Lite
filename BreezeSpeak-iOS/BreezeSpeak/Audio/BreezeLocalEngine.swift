//
//  BreezeLocalEngine.swift
//  BreezeSpeak
//
//  与 macOS 版同源的本地推理引擎：直接链接 vendor 进来的 Breeze-TTS-2 C++ 核心
//  （ggml + Metal），把 GGUF 权重跑在 iPad 的 GPU 上，全程离线、无任何上报。
//
//  三层职责：
//    BreezeEngineCore   非主线程的串行上下文，负责加载权重与阻塞式推理
//    BreezePrompt       Breeze 原生标记 → 引擎能听懂的文本 / 指令
//    BreezeLocalEngine  TTSEngine 适配，把流式 chunk 交给 UI
//

import Foundation

// MARK: - 引擎上下文

/// 持有 C 上下文的对象。整个 App 只加载一次权重，反复复用。
/// 引擎不可重入，所以加载与推理由同一条串行队列驱动。
final class BreezeEngineCore {
    static let shared = BreezeEngineCore()

    private let queue = DispatchQueue(label: "com.breezespeak.engine", qos: .userInitiated)
    private let lock = NSLock()
    private var engine: BreezeEngine?
    private var loadedPath: String?
    private var cancelFlag = false
    private var lastLoadSeconds: Double?
    private var lastFactor: Double?
    private var lastElapsed: Double?

    private init() {
        // ggml 默认只开 4 个 CPU 线程，而这台机器有 8 个核：4 个大核 + 4 个能效核。
        // 实测在这颗 M 芯片上开 6 个比 4 个快约 13%（开 8 个反而回落，能效核会被大核拖住）。
        // 引擎只认环境变量，所以必须在 breeze_init 之前塞进进程环境。
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let threads = cores >= 8 ? 6 : max(2, cores - 2)
        setenv("BREEZE_CPU_THREADS", String(threads), 1)
    }

    /// 最近一次真实加载（非复用）的耗时，喂给生成耗时估算
    var measuredLoadSeconds: Double? {
        lock.lock(); defer { lock.unlock() }
        return lastLoadSeconds
    }

    /// 最近一次推理的实时率（音频时长 ÷ 墙钟耗时），喂给生成耗时估算
    var measuredRealtimeFactor: Double? {
        lock.lock(); defer { lock.unlock() }
        return lastFactor
    }

    /// 最近一次推理的墙钟耗时（秒），写性能日志用
    var measuredElapsed: Double? {
        lock.lock(); defer { lock.unlock() }
        return lastElapsed
    }

    var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return engine != nil
    }

    var currentPath: String? {
        lock.lock(); defer { lock.unlock() }
        return loadedPath
    }

    /// 引擎真实跑在哪个后端上（Metal 初始化失败会静默回退 CPU，这里能查到）
    var backendName: String? {
        lock.lock(); defer { lock.unlock() }
        return engine?.backendName
    }

    /// 加载 / 换模型。已经是同一个文件就直接返回。
    func load(path: String, useGPU: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.lock.lock()
                let reuse = (self.engine != nil && self.loadedPath == path)
                self.lock.unlock()
                if reuse {
                    continuation.resume()
                    return
                }

                self.lock.lock()
                let previous = self.engine
                self.engine = nil
                self.loadedPath = nil
                self.lock.unlock()
                previous?.shutdown()

                let started = Date()
                let created = BreezeEngine(modelPath: path, useGPU: useGPU)
                guard let created else {
                    let detail = BreezeEngine.lastErrorMessage()
                    let message = detail.isEmpty ? "权重加载失败" : detail
                    continuation.resume(throwing: TTSError.synthesisFailed(message))
                    return
                }
                // 整段一次解码，避免流式分块反复重解码左上下文（详见 AppConfig）
                created.chunkFrames = AppConfig.decodeChunkFrames

                self.lock.lock()
                self.engine = created
                self.loadedPath = path
                self.lastLoadSeconds = Date().timeIntervalSince(started)
                self.lock.unlock()
                NSLog("BreezeSpeak: GGUF 加载完成，用时 %.1fs，采样率 %d Hz",
                      Date().timeIntervalSince(started), Int(created.sampleRate))
                continuation.resume()
            }
        }
    }

    func unload() {
        // 必须排到那条串行队列上：推理进行中直接把 ctx 释放掉，
        // 引擎线程下一次访问就是野指针。排队之后最坏情况是等本次推理跑完再释放，
        // 内存警告 / 手动释放都能安全落在推理结束之后。
        queue.async {
            self.lock.lock()
            let previous = self.engine
            self.engine = nil
            self.loadedPath = nil
            self.lastLoadSeconds = nil
            self.lastFactor = nil
            self.lock.unlock()
            previous?.shutdown()
        }
    }

    func cancel() {
        lock.lock()
        cancelFlag = true
        lock.unlock()
    }

    func resetCancel() {
        lock.lock()
        cancelFlag = false
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelFlag
    }

    /// 阻塞式推理，chunk 在引擎线程上回调（24 kHz 单声道 float32）。
    /// 采样累计交给调用方，避免这里再复制一份几 MB 的数组。
    /// 阻塞式推理，chunk 在引擎线程上回调（24 kHz 单声道 float32）。
    /// 传出去的是引擎缓冲的临时视图，只在回调内有效，调用方不得持有。
    func generate(text: String,
                  instruction: String,
                  refText: String?,
                  refSamples: [Float]?,
                  cfgScale: Float,
                  seed: Int,
                  maxNewTokens: Int,
                  splitChars: Int,
                  temperature: Float = 0,
                  topK: Int = 0,
                  topP: Float = 0,
                  repetitionPenalty: Float = 0,
                  onChunk: @escaping (UnsafeBufferPointer<Float>) -> Void) async throws {
        resetCancel()

        lock.lock()
        let current = engine
        lock.unlock()
        guard let current else { throw TTSError.modelNotReady }

        let refData: Data? = {
            guard let refSamples, !refSamples.isEmpty else { return nil }
            return refSamples.withUnsafeBufferPointer { Data(buffer: $0) }
        }()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let started = Date()
                var produced = 0
                let ok = current.generate(
                    withText: text,
                    instruction: instruction,
                    refText: refText,
                    refAudioSamples: refData,
                    cfgScale: cfgScale,
                    seed: seed,
                    maxNewTokens: maxNewTokens,
                    splitChars: splitChars,
                    temperature: temperature,
                    topK: topK,
                    topP: topP,
                    repetitionPenalty: repetitionPenalty,
                    onChunk: { payload, stop in
                        let count = payload.count / MemoryLayout<Float>.size
                        guard count > 0 else { return }
                        if self.isCancelled {
                            stop.pointee = true
                        }
                        produced += count
                        // 直接把引擎缓冲当 float 视图传出去，不建中间数组：
                        // 采样累加与波形增量各取一次，全程零额外拷贝。
                        (payload as Data).withUnsafeBytes { raw in
                            onChunk(raw.bindMemory(to: Float.self))
                        }
                    }
                )

                let elapsed = Date().timeIntervalSince(started)
                let seconds = Double(produced) / 24_000
                let factor = seconds / max(elapsed, 0.001)
                self.lock.lock()
                self.lastFactor = factor
                self.lastElapsed = elapsed
                self.lock.unlock()
                NSLog("BreezeSpeak: 推理 %.2fs 音频耗时 %.2fs (%.1fx 实时)",
                      seconds, elapsed, factor)

                if !ok && !self.isCancelled {
                    let detail = BreezeEngine.lastErrorMessage()
                    let message = detail.isEmpty ? "推理失败" : detail
                    continuation.resume(throwing: TTSError.synthesisFailed(message))
                    return
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - 原生标记处理

/// 把用户输入整理成引擎能直接消费的两种东西：文本与演绎指令。
///
/// 取舍说明：这套 C++ 引擎的原生标记与 MLX 版略有差异 ——
/// `|` / `||` 没有专门的停顿 token，所以映射成逗号与句号（听感等效且稳定）；
/// `(slow)` / `(fast)` 转成语速指令；`(whisper)` 交给引擎的副语言标签；
/// `[笑]` `[叹气]` 这类方括号标记原样保留，由模型渲染。
enum BreezePrompt {
    struct Prepared {
        var text: String
        var paceFactor: Double
        var keptMarkers: Bool
    }

    static func prepare(_ raw: String) -> Prepared {
        var output = ""
        var pace: Double = 1
        var keptMarkers = false

        let characters = Array(raw)
        var index = 0

        func dropTrailingSpaces() {
            while output.last == " " { output.removeLast() }
        }

        while index < characters.count {
            let character = characters[index]

            if character == "[" {
                if let closing = characters[index...].firstIndex(of: "]") {
                    let token = String(characters[(index + 1)..<closing])
                    // [spk_N] 是老 UI 里的音色选择语法，本引擎用声线卡片表达，直接丢弃
                    if !token.hasPrefix("spk_") {
                        output.append("[\(token)]")
                        keptMarkers = true
                    }
                    index = closing + 1
                    continue
                }
            }

            if character == "(" || character == "（" {
                let closingCharacter: Character = character == "(" ? ")" : "）"
                if let closing = characters[index...].firstIndex(of: closingCharacter) {
                    let token = String(characters[(index + 1)..<closing]).lowercased()
                    switch token {
                    case "slow", "慢速":
                        pace *= 0.85
                    case "fast", "加速":
                        pace *= 1.16
                    case "whisper", "轻声":
                        output.append("(whispering)")
                        keptMarkers = true
                    default:
                        // 其余圆括号内容（(laugh) 之类）当副语言交给模型
                        output.append("(\(token))")
                        keptMarkers = true
                    }
                    index = closing + 1
                    continue
                }
            }

            if character == "|" {
                var long = false
                if index + 1 < characters.count, characters[index + 1] == "|" {
                    long = true
                    index += 1
                }
                dropTrailingSpaces()
                output.append(long ? "。" : "，")
                index += 1
                continue
            }

            if character == "\n" {
                dropTrailingSpaces()
                output.append("。")
                index += 1
                continue
            }

            output.append(character)
            index += 1
        }

        // 句号连排会让模型停顿过长
        var cleaned = ""
        for character in output {
            if character == "。", cleaned.last == "。" { continue }
            if character == "，", cleaned.last == "，" || cleaned.last == "。" { continue }
            cleaned.append(character)
        }

        return Prepared(text: cleaned.trimmingCharacters(in: .whitespacesAndNewlines),
                        paceFactor: pace,
                        keptMarkers: keptMarkers)
    }

    /// 声线本身固定的描述（造声 / 内置音色）
    static func voiceInstruction(for voice: VoiceProfile) -> String {
        switch voice.kind {
        case .builtin:
            return voice.nativeInstruction ?? voice.descriptor
        case .design:
            return voice.descriptor
        case .clone:
            // 音色由参考音频决定，这里只放用户写的文字微调（语气 / 语速 / 气息）
            return (voice.tweak ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// 把「声线描述 + 演绎指令 + 语速」合成一条 instruction
    static func compose(voice: VoiceProfile,
                        direction: String,
                        speed: Double,
                        paceFactor: Double) -> String {
        var parts: [String] = []
        let base = voiceInstruction(for: voice).trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { parts.append(base) }

        let directed = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !directed.isEmpty { parts.append(directed) }

        let effective = speed * paceFactor
        if effective < 0.94 {
            parts.append("Speak noticeably slower than your natural pace.")
        } else if effective > 1.09 {
            parts.append("Speak a little faster than your usual pace.")
        }

        if parts.isEmpty { return "Speak clearly and naturally." }
        return parts.joined(separator: " ")
    }
}

// MARK: - TTSEngine 适配

@MainActor
final class BreezeLocalEngine: TTSEngine {
    let isNeural = true

    var displayName: String {
        "Breeze TTS 2 · \(model.selectedTier.shortName) · \(backendLabel)"
    }

    /// 实际走的后端。优先问引擎自己（`breeze_backend_name`），
    /// 拿不到再退回请求值——闭源库里 Metal 初始化失败会静默回退 CPU，请求值会骗人。
    var backendLabel: String {
        if let actual = core.backendName, !actual.isEmpty { return actual }
        return prefersGPU ? "GPU" : "CPU"
    }

    /// 权重是否已常驻（供预热判断）
    var isLoaded: Bool { BreezeEngineCore.shared.isLoaded }

    private let model: ModelManager
    private let core = BreezeEngineCore.shared
    private var referenceCache: [String: [Float]] = [:]

    init(model: ModelManager) {
        self.model = model
    }

    // MARK: 加载

    /// 是否把 useGPU=YES 传给引擎。固定在 InferenceBackend 里，默认 CPU（实测更快）。
    private var prefersGPU: Bool { InferenceBackend.usesGPU }

    func prepare(voice: VoiceProfile?) async throws {
        guard let url = model.readyModelURL else { throw TTSError.modelNotReady }
        if core.currentPath == url.path { return }
        try await core.load(path: url.path, useGPU: prefersGPU)
        if let load = core.measuredLoadSeconds {
            GenerationEstimator.record(loadSeconds: load, tierID: model.selectedTier.id)
        }
    }

    func unload() {
        core.unload()
        referenceCache.removeAll()
    }

    func trimCache() {
        // 权重由 BreezeEngineCore 常驻，参考音频最多 30 秒（约 3 MB），留着下次直接用；
        // 这里没有可回收的中间激活，真正要腾内存走 unload()
    }

    func cancel() {
        core.cancel()
    }

    // MARK: 推理

    func synthesize(
        _ request: TTSRequest,
        onProgress: @escaping (Double) -> Void,
        onPartial: @escaping (TTSResult) -> Void,
        onChunk: ((UnsafeBufferPointer<Float>) -> Void)?
    ) async throws -> TTSResult {
        try await prepare(voice: request.voice)

        let prepared = BreezePrompt.prepare(request.text)
        guard !prepared.text.isEmpty else { throw TTSError.emptyText }

        let instruction = BreezePrompt.compose(
            voice: request.voice,
            direction: request.direction,
            speed: request.speed,
            paceFactor: prepared.paceFactor
        )

        let reference = try referenceSamples(for: request.voice)
        let estimated = TextSegmenter.estimatedSpeechSeconds(request.text)

        // chunk 在引擎线程到达，这里只做累加与节流上报；真正的 UI 刷新走主线程。
        // 中间过程不再回吐「全部累积采样」——那会让每次刷新都复制几 MB 数组，
        // 长音频下累积成 O(n²) 的内存拷贝，直接拖慢推理。
        let box = SampleBox()

        try await core.generate(
            text: prepared.text,
            instruction: instruction,
            refText: reference?.text,
            refSamples: reference?.samples,
            cfgScale: Float(request.guidanceScale),
            seed: request.sampling.seed,
            maxNewTokens: 0,
            // 交给引擎按句分段。传 0 表示「整段一次推完」，长文本会因
            // 文本编码器的 T×T 注意力掩码爆内存、并撞上 60 秒的 max_new_tokens 上限。
            // 详见 AppConfig.splitChars。
            splitChars: AppConfig.splitChars,
            // 显式把采样参数送进引擎。传 0 等于「沿用 gguf 自带设置」，
            // 也就是每帧在几十个候选里随机抽——那正是「同一句提示词、每次声音都不一样」的根源。
            temperature: Float(request.sampling.temperature),
            topK: request.sampling.topK,
            topP: Float(request.sampling.topP),
            repetitionPenalty: Float(request.sampling.repetitionPenalty),
            onChunk: { chunk in
                box.append(contentsOf: chunk)
                onChunk?(chunk)
                guard box.shouldReport() else { return }
                let rate = Double(box.count) / AppConfig.sampleRate
                Task { @MainActor in
                    onProgress(min(0.97, max(0.02, rate / max(estimated, 0.6))))
                }
            }
        )

        let rawSamples = box.takeAll()
        guard !rawSamples.isEmpty else {
            if core.isCancelled { throw TTSError.cancelled }
            throw TTSError.synthesisFailed("模型没有返回音频")
        }

        // 兜底：codec 语言模型在贪心解码下偶尔会连续吐出「静音 / 填充」token，
        // 形成 2~3 秒纯数字静音（听感就是讲一半卡住）。采样端把 repetitionPenalty
        // 恢复成 1.15 已能避免绝大多数退化，这里再把长文本里残留的 0.8~1.1 秒
        // 句间停顿压到自然范围，双保险确保任何文本都不会顿住。压缩是纯函数，
        // 不影响「同提示词同声音」；首尾呼吸与 0.3~0.5s 的正常标点停顿保留。
        let samples = AudioMath.collapseLongSilences(rawSamples, sampleRate: AppConfig.sampleRate)
        if samples.count != rawSamples.count {
            NSLog("BreezeSpeak: 静音压缩 %.2fs -> %.2fs",
                  Double(rawSamples.count) / AppConfig.sampleRate,
                  Double(samples.count) / AppConfig.sampleRate)
        }

        // 把本次实测的实时率回填给估算器（指数平滑）
        if let factor = core.measuredRealtimeFactor {
            GenerationEstimator.record(realtimeFactor: factor, tierID: model.selectedTier.id)
        }

        if let elapsed = core.measuredElapsed {
            PerformanceLog.record(
                backend: backendLabel,
                // 记实际送进引擎的文件名，而不是 UI 选中的档位：
                // 两者不一致时（选了 A 档但加载了 B 档）日志要能自证。
                tier: core.currentPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? model.selectedTier.shortName,
                audioSeconds: Double(samples.count) / AppConfig.sampleRate,
                elapsed: elapsed,
                characters: request.text.count
            )
        }

        guard samples.count > 2_400 else {
            throw TTSError.synthesisFailed("音频过短，可能是权重文件不完整")
        }

        onProgress(1)
        onPartial(TTSResult(samples: samples, sampleRate: AppConfig.sampleRate))
        return TTSResult(samples: AudioMath.normalize(samples, target: 0.92),
                         sampleRate: AppConfig.sampleRate)
    }

    // MARK: 参考音频

    private func referenceSamples(for voice: VoiceProfile) throws -> (samples: [Float], text: String)? {
        if voice.kind == .clone {
            guard let fileName = voice.referenceFileName else {
                throw TTSError.audioUnreadable("这条克隆声线缺少参考音频，请重新导入。")
            }
            return try referenceSamples(named: fileName,
                                        text: voice.referenceText,
                                        missingTextHint: "克隆需要参考文稿，请在声线实验室补上原文。")
        }

        // 内置 / 造声：如果有锚定音频，就把它当成克隆参考。
        // 音色由这段参考决定，不再由「这次要读什么」决定——
        // 光靠固定 seed 只能保证同一段文字可复现，换了文字照样会换一个人。
        guard let anchor = VoiceAnchor.load(for: voice) else { return nil }
        let key = "anchor:" + voice.id.uuidString
        if let cached = referenceCache[key] { return (cached, anchor.text) }
        referenceCache[key] = anchor.samples
        return anchor
    }

    private func referenceSamples(named fileName: String,
                                  text rawText: String?,
                                  missingTextHint: String) throws -> (samples: [Float], text: String) {
        let text = (rawText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TTSError.audioUnreadable(missingTextHint)
        }

        if let cached = referenceCache[fileName] {
            return (cached, text)
        }

        let url = AppPaths.referencesDirectory.appendingPathComponent(fileName)
        let decoded = try WAVFile.read(url: url)
        guard !decoded.samples.isEmpty else {
            throw TTSError.audioUnreadable("参考音频读不出采样数据。")
        }
        let capped = Array(decoded.samples.prefix(Int(AppConfig.maxReferenceSeconds * AppConfig.sampleRate)))
        referenceCache[fileName] = capped
        return (capped, text)
    }
}

// MARK: - 流式采样累加

/// 引擎线程写、主线程读的采样缓冲。上报节流到 ~8 Hz，避免长文本时主线程被刷新淹没。
final class SampleBox {
    private let lock = NSLock()
    private var storage: [Float] = []
    private var lastReport = Date.distantPast

    func append(_ chunk: [Float]) {
        lock.lock()
        storage.append(contentsOf: chunk)
        lock.unlock()
    }

    /// 直接接引擎缓冲，省掉一次中间数组
    func append(contentsOf buffer: UnsafeBufferPointer<Float>) {
        lock.lock()
        storage.append(contentsOf: buffer)
        lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    /// 取走全部采样并清空（结束时调用，避免再留一份副本）
    func takeAll() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let result = storage
        storage = []
        return result
    }

    /// 距上次上报超过 120ms 才放行；频率已经足够更新进度条，再密就是浪费
    func shouldReport() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.12 else { return false }
        lastReport = now
        return true
    }
}
