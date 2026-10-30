//
//  SystemSpeechEngine.swift
//  BreezeSpeak
//
//  系统离线语音兜底引擎。
//  作用：模型未就绪 / 未链接 MLXAudio 时，App 依然可以完整跑通「输入 → 生成 → 播放 → 导出 → 历史」。
//  它会把声纹参数（音高 / 语速 / 气声 / 增益）映射到 AVSpeechSynthesizer，
//  因此不同声线在兜底模式下也能听出区别。
//

import Foundation
import AVFoundation

@MainActor
final class SystemSpeechEngine: TTSEngine {
    let displayName = "系统离线语音 · 兜底"
    let isNeural = false

    private let synthesizer = AVSpeechSynthesizer()
    private var cancelled = false

    private static let voicePool: [AVSpeechSynthesisVoice] = {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let chinese = all.filter { $0.language.hasPrefix("zh") }
        let pool = chinese.isEmpty ? all : chinese
        return pool.sorted { lhs, rhs in
            lhs.quality.rawValue > rhs.quality.rawValue
        }
    }()

    func prepare(voice: VoiceProfile?) async throws {}

    func synthesize(
        _ request: TTSRequest,
        onProgress: @escaping (Double) -> Void,
        onPartial: @escaping (TTSResult) -> Void,
        onChunk: ((UnsafeBufferPointer<Float>) -> Void)?
    ) async throws -> TTSResult {
        cancelled = false
        let parsed = TextSegmenter.parse(request.text)
        let segments = parsed.segments
        guard !segments.isEmpty else { throw TTSError.emptyText }

        var accumulated: [Float] = []
        var completed = 0.0

        for segment in segments {
            if cancelled || Task.isCancelled { throw TTSError.cancelled }

            let spoken = TextSegmenter.plainText(segment.text)
            if !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let samples = try await renderSegment(
                    spoken,
                    voice: request.voice,
                    modifier: segment.modifier,
                    speed: request.speed,
                    direction: request.direction
                )
                accumulated = AudioMath.append(
                    accumulated,
                    with: samples,
                    sampleRate: AppConfig.sampleRate,
                    fade: AppConfig.crossfadeSeconds
                )
            }

            if segment.pauseAfter > 0 {
                accumulated.append(contentsOf: AudioMath.silence(seconds: segment.pauseAfter, sampleRate: AppConfig.sampleRate))
            }

            completed += 1
            onProgress(min(1, completed / Double(segments.count)))
            onPartial(TTSResult(samples: accumulated, sampleRate: AppConfig.sampleRate))
        }

        guard !accumulated.isEmpty else { throw TTSError.synthesisFailed("未能生成有效音频") }
        return TTSResult(samples: AudioMath.normalize(accumulated, target: 0.88), sampleRate: AppConfig.sampleRate)
    }

    func unload() {
        cancelled = true
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func cancel() {
        cancelled = true
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - 单段渲染

    private func renderSegment(
        _ text: String,
        voice: VoiceProfile,
        modifier: SpeechModifier,
        speed: Double,
        direction: String
    ) async throws -> [Float] {
        let signature = voice.signature
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = pickVoice(for: voice)

        // pitchMultiplier 有效范围 0.5 ~ 2.0
        let directionTone = DirectionTone(direction: direction)
        let pitch = min(2.0, max(0.5, signature.pitch * directionTone.pitchFactor))
        utterance.pitchMultiplier = Float(pitch)

        let rate = signature.rate * speed * modifier.rateFactor * directionTone.rateFactor
        utterance.rate = Float(min(Double(AVSpeechUtteranceMaximumSpeechRate),
                                   max(Double(AVSpeechUtteranceMinimumSpeechRate),
                                       Double(AVSpeechUtteranceDefaultSpeechRate) * rate)))
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        let timeout = max(8, TextSegmenter.estimatedSpeechSeconds(text) * 3 + 4)
        let rendered = try await render(utterance, timeout: timeout)
        guard !rendered.samples.isEmpty else {
            throw TTSError.synthesisFailed("系统语音未返回音频数据")
        }

        var samples = AudioMath.resample(rendered.samples, from: rendered.sampleRate, to: AppConfig.sampleRate)
        let gain = Float(signature.gain * modifier.gainFactor) * (1 - Float(signature.breathiness) * 0.22)
        samples = AudioMath.applyGain(samples, max(0.2, gain))
        // 轻声模式：加一点低通，听感更“贴耳”
        if modifier == .whisper || signature.breathiness > 0.6 {
            samples = Self.softLowPass(samples)
        }
        return samples
    }

    private func pickVoice(for voice: VoiceProfile) -> AVSpeechSynthesisVoice? {
        guard !Self.voicePool.isEmpty else { return nil }
        let index = Int(voice.signature.seed % UInt64(Self.voicePool.count))
        return Self.voicePool[index]
    }

    private func render(_ utterance: AVSpeechUtterance, timeout: Double) async throws -> (samples: [Float], sampleRate: Double) {
        let collector = SampleCollector()
        return await withCheckedContinuation { (continuation: CheckedContinuation<(samples: [Float], sampleRate: Double), Never>) in
            collector.attach(continuation)
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                collector.consume(pcm)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                collector.finish()
            }
        }
    }

    private static func softLowPass(_ samples: [Float]) -> [Float] {
        guard samples.count > 4 else { return samples }
        var output = samples
        var previous = samples[0]
        let alpha: Float = 0.28
        for index in 1..<samples.count {
            previous += alpha * (samples[index] - previous)
            output[index] = previous
        }
        return output
    }
}

// MARK: - 方向指令的轻量映射

struct DirectionTone {
    var pitchFactor: Double = 1
    var rateFactor: Double = 1

    init(direction: String) {
        guard !direction.isEmpty else { return }
        let text = direction.lowercased()

        if text.contains("激动") || text.contains("兴奋") || text.contains("高亢") {
            pitchFactor *= 1.06
            rateFactor *= 1.08
        }
        if text.contains("低落") || text.contains("悲伤") || text.contains("沉重") {
            pitchFactor *= 0.95
            rateFactor *= 0.92
        }
        if text.contains("温柔") || text.contains("轻声") || text.contains("安抚") {
            rateFactor *= 0.94
        }
        if text.contains("快速") || text.contains("急促") {
            rateFactor *= 1.1
        }
        if text.contains("缓慢") || text.contains("放慢") {
            rateFactor *= 0.88
        }
        if text.contains("严肃") || text.contains("播报") {
            pitchFactor *= 0.98
            rateFactor *= 0.98
        }
    }
}

// MARK: - 采样收集器

/// AVSpeechSynthesizer.write 的回调在后台线程，且不保证一定送空 buffer，需要锁 + 超时兜底。
private final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 22_050
    private var finished = false
    private var continuation: CheckedContinuation<(samples: [Float], sampleRate: Double), Never>?

    func attach(_ continuation: CheckedContinuation<(samples: [Float], sampleRate: Double), Never>) {
        lock.lock()
        if finished {
            let payload = (samples: samples, sampleRate: rate)
            lock.unlock()
            continuation.resume(returning: payload)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        if buffer.frameLength == 0 {
            finish()
            return
        }
        let mono = AudioMath.monoSamples(from: buffer)
        let sampleRate = buffer.format.sampleRate
        lock.lock()
        guard !finished else { lock.unlock(); return }
        rate = sampleRate
        samples.append(contentsOf: mono)
        lock.unlock()
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let payload = (samples: samples, sampleRate: rate)
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: payload)
    }
}
