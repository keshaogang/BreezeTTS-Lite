//
//  SpeechRuntime.swift
//  BreezeSpeak
//
//  引擎生命周期管理：权重就绪时用同源的 Breeze C++ 引擎（ggml + Metal），
//  权重缺失时才回落到系统离线语音，保证界面永远可用。
//

import Foundation
import SwiftUI

@MainActor
final class SpeechRuntime: ObservableObject {
    @Published private(set) var engineLabel: String = ""
    @Published private(set) var isNeural: Bool = false
    @Published private(set) var note: String = ""

    private let model: ModelManager
    private var engine: TTSEngine?

    init(model: ModelManager) {
        self.model = model
        refresh()
    }

    func refresh() {
        let wantsNeural = model.isReady
        let neuralActive = engine is BreezeLocalEngine

        if engine == nil || neuralActive != wantsNeural {
            let previous = engine
            engine = wantsNeural ? BreezeLocalEngine(model: model) : SystemSpeechEngine()
            previous?.unload()
        }

        isNeural = engine?.isNeural ?? false
        engineLabel = engine?.displayName ?? "系统离线语音"

        if wantsNeural {
            note = "GGUF 本地推理 · \(InferenceBackend.label) · 断网可用"
        } else if model.isDownloading {
            note = "权重下载中 · 暂用系统语音"
        } else {
            note = "未下载权重 · 暂用系统语音"
        }
    }

    var activeEngine: TTSEngine {
        if let engine { return engine }
        let fallback = SystemSpeechEngine()
        engine = fallback
        return fallback
    }

    /// 权重是否已经常驻（决定第一次生成要不要再等一次加载）
    var isEngineLoaded: Bool {
        (engine as? BreezeLocalEngine)?.isLoaded ?? false
    }

    /// 预热：提前把权重 mmap 进来、把 Metal pipeline 编译好。
    /// 冷加载真机约 3 秒、首次安装冷读约 17 秒，第一次生成时再等非常难受，
    /// 所以在模型就绪 / 回到前台时空闲加载一次。
    func warmUpIfNeeded() async {
        guard isNeural, model.isReady, !isEngineLoaded else { return }
        // 用设备总内存判断值不值得预热，不要用 os_proc_available_memory()：
        // 那个值在权重常驻后本来就只剩几百 MB，拿它做门槛会导致热身永远被跳过。
        let physical = Double(ProcessInfo.processInfo.physicalMemory)
        guard Double(model.selectedTier.peakBytes) < physical * 0.6 else { return }
        try? await activeEngine.prepare(voice: nil)
    }

    func synthesize(
        _ request: TTSRequest,
        onProgress: @escaping (Double) -> Void,
        onPartial: @escaping (TTSResult) -> Void,
        onChunk: ((UnsafeBufferPointer<Float>) -> Void)? = nil
    ) async throws -> TTSResult {
        refresh()

        let engine = activeEngine

        // 音色锚定：内置 / 造声声线第一次出声前，先用一句固定的话把音色钉下来。
        //
        // 只固定采样是不够的：实测同一段声音描述、两段不同文字，基频中位数从 226 Hz
        // 跳到 308 Hz，频谱包络相似度只有 0.63 —— 换了文字就是换了个人。
        // 把首次生成的音频留作参考音频（ref_audio + ref_text），之后每次走克隆分支，
        // 音色由这段参考决定，才真正稳定。
        //
        // 必须在算缓存键之前做：键里带了「有没有锚点」，做完锚点才不会把
        // 「有锚点」的结果记到「无锚点」的键上。
        var progressFloor: Double = 0
        if request.sampling == .locked,
           !request.isPreview,
           request.voice.kind != .clone,
           engine is BreezeLocalEngine,
           !VoiceAnchor.exists(for: request.voice) {
            await createAnchor(for: request.voice, engine: engine, onProgress: onProgress)
            progressFloor = 0.12
        }

        // 同输入直接复用上次的音频：保证「同一提示词听起来是同一个声音」，
        // 同时把重复生成的耗时降到接近 0。
        let cacheKey = AudioCache.key(for: request)
        if let cached = AudioCache.load(key: cacheKey, sampleRate: AppConfig.sampleRate) {
            PerformanceLog.record(
                backend: "缓存命中",
                tier: model.selectedTier.shortName,
                audioSeconds: cached.duration,
                elapsed: 0.001,
                characters: request.text.count
            )
            onProgress(1)
            onPartial(cached)
            return cached
        }

        let result = try await engine.synthesize(
            request,
            onProgress: { progressFloor > 0 ? onProgress(progressFloor + (1 - progressFloor) * $0) : onProgress($0) },
            onPartial: onPartial,
            onChunk: onChunk
        )
        AudioCache.store(result, key: cacheKey)
        trimMemory()
        return result
    }

    /// 用一句固定的话生成锚点音频并落盘。失败就静默跳过——退回没有锚点的老行为，
    /// 用户至少还能出声，只是音色会随文字漂移。
    private func createAnchor(for voice: VoiceProfile,
                              engine: TTSEngine,
                              onProgress: @escaping (Double) -> Void) async {
        let request = TTSRequest(
            text: VoiceAnchor.anchorText,
            voice: voice,
            direction: "",
            guidanceScale: max(voice.guidanceScale, AppConfig.defaultGuidanceScale),
            speed: voice.speed,
            sampling: .locked
        )
        let result = try? await engine.synthesize(
            request,
            onProgress: { onProgress(0.01 + $0 * 0.10) },
            onPartial: { _ in }
        )
        if let result {
            VoiceAnchor.store(result, for: voice)
        }
    }

    /// 推理结束释放参考音频缓存与中间缓冲，权重保留
    func trimMemory() {
        if let local = engine as? BreezeLocalEngine {
            local.trimCache()
        }
    }

    /// 完全卸载（低内存 / 清空缓存时调用）
    func unloadAll() {
        engine?.unload()
        engine = nil
        refresh()
    }

    /// 切换推理后端后必须重新加载权重：后端是在 breeze_init 时定死的，
    /// 不重载的话改了设置也不会生效。
    func reloadForBackendChange() async {
        unloadAll()
        await warmUpIfNeeded()
        refresh()
    }

    func cancelCurrent() {
        if let local = engine as? BreezeLocalEngine {
            local.cancel()
        }
        if let system = engine as? SystemSpeechEngine {
            system.cancel()
        }
    }
}
