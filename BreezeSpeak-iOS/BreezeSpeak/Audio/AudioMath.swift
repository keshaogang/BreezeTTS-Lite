//
//  AudioMath.swift
//  BreezeSpeak
//
//  PCM 处理与轻量声学分析：重采样、拼接、波形峰值、信噪比、基频估计。
//  克隆声纹的“音色参数”就是从这里量出来的。
//

import Foundation
import AVFoundation

enum AudioMath {
    /// 多声道混为单声道 Float
    static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return [] }

        var output = [Float](repeating: 0, count: frames)

        if let floatData = buffer.floatChannelData {
            for channel in 0..<channels {
                let pointer = floatData[channel]
                for frame in 0..<frames {
                    output[frame] += pointer[frame]
                }
            }
        } else if let int16Data = buffer.int16ChannelData {
            for channel in 0..<channels {
                let pointer = int16Data[channel]
                for frame in 0..<frames {
                    output[frame] += Float(pointer[frame]) / 32_768
                }
            }
        } else if let int32Data = buffer.int32ChannelData {
            for channel in 0..<channels {
                let pointer = int32Data[channel]
                for frame in 0..<frames {
                    output[frame] += Float(pointer[frame]) / 2_147_483_648
                }
            }
        }

        if channels > 1 {
            let scale = 1 / Float(channels)
            for index in 0..<frames { output[index] *= scale }
        }
        return output
    }

    /// 线性插值重采样（语音场景足够，避免引入额外依赖）
    static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > 0, targetRate > 0 else { return [] }
        if abs(sourceRate - targetRate) < 0.5 { return samples }

        let ratio = sourceRate / targetRate
        let outputCount = Int((Double(samples.count) / ratio).rounded())
        guard outputCount > 1 else { return samples }

        var output = [Float](repeating: 0, count: outputCount)
        let lastIndex = samples.count - 1
        for index in 0..<outputCount {
            let position = Double(index) * ratio
            let lower = Int(position)
            let fraction = Float(position - Double(lower))
            let upper = min(lower + 1, lastIndex)
            output[index] = samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
        return output
    }

    static func silence(seconds: Double, sampleRate: Double) -> [Float] {
        let count = max(0, Int(seconds * sampleRate))
        return [Float](repeating: 0, count: count)
    }

    static func applyGain(_ samples: [Float], _ gain: Float) -> [Float] {
        guard gain != 1 else { return samples }
        return samples.map { $0 * gain }
    }

    /// 归一化到目标峰值，避免不同引擎响度差异过大
    static func normalize(_ samples: [Float], target: Float = 0.9) -> [Float] {
        guard let maxValue = samples.map({ abs($0) }).max(), maxValue > 0.0001 else { return samples }
        let gain = min(4, target / maxValue)
        return applyGain(samples, gain)
    }

    static func softClip(_ sample: Float) -> Float {
        if sample > 0.95 { return 0.95 + (sample - 0.95) * 0.2 }
        if sample < -0.95 { return -0.95 + (sample + 0.95) * 0.2 }
        return sample
    }

    /// 压缩异常长的内部静音，消除「讲一半顿几秒才说完」。
    ///
    /// 背景：codec 语言模型在贪心解码下偶尔会连续吐出「静音 / 填充」token，
    /// 形成 2~3 秒的纯数字静音段（听感就是讲一半卡住）。采样端恢复
    /// `repetitionPenalty` 已经能避免绝大多数情况，但长文本、特殊声线仍可能
    /// 残留 0.8~1 秒以上的句间停顿。这里做一道音频后处理兜底：
    ///   - 用 20ms 分帧 RMS 找静音段，阈值自适应到峰值的一定比例；
    ///   - 只有「内部」且超过 `maxPause` 的静音才压缩，首尾静音保留一小段，
    ///     标点处 0.3~0.5 秒的自然呼吸停顿不动；
    ///   - 超长段保留开头 `maxPause` 长度，其余删掉，接缝两侧都是静音区，
    ///     天然平滑，不需要额外淡化。
    ///
    /// 纯函数、确定性：同样的输入永远得到同样的输出，不影响「同提示词同声音」。
    /// - Parameters:
    ///   - maxPause: 允许保留的最长内部静音（秒）。默认 0.5，比正常逗号停顿
    ///     （0.3~0.46s）宽松，只压 0.5s 以上的异常段。实测长文本 0.8~1.1s 的
    ///     句间停顿会被收到 0.5s，短句 0.56s 的标点停顿几乎不动。
    ///   - thresholdRatio: 静音判定阈值 = 峰值 RMS × 此比例。默认 0.04。
    ///   - keepHead/keepTail: 首尾静音保留长度（秒），避免切除起始/结束的呼吸声。
    static func collapseLongSilences(_ samples: [Float],
                                     sampleRate: Double,
                                     maxPause: Double = 0.5,
                                     thresholdRatio: Float = 0.04,
                                     keepHead: Double = 0.06,
                                     keepTail: Double = 0.18) -> [Float] {
        let frame = max(1, Int(sampleRate * 0.02)) // 20ms
        let count = samples.count
        guard count > frame * 4, maxPause > 0 else { return samples }

        // 逐帧 RMS
        var framesStart: [Int] = []
        framesStart.reserveCapacity(count / frame)
        var rms: [Float] = []
        rms.reserveCapacity(count / frame)
        var index = 0
        while index + frame <= count {
            var sum: Double = 0
            for cursor in index..<(index + frame) {
                let v = Double(samples[cursor])
                sum += v * v
            }
            framesStart.append(index)
            rms.append(Float((sum / Double(frame)).squareRoot()))
            index += frame
        }
        guard let peak = rms.max(), peak > 0.000_001 else { return samples }
        let threshold = peak * thresholdRatio

        // 找连续静音段（帧区间，左闭右开）
        var runs: [(Int, Int)] = []
        var start: Int? = nil
        for (i, value) in rms.enumerated() {
            if value < threshold {
                if start == nil { start = i }
            } else if let s = start {
                runs.append((s, i)); start = nil
            }
        }
        if let s = start { runs.append((s, rms.count)) }
        guard !runs.isEmpty else { return samples }

        let maxFrames = max(1, Int(maxPause / 0.02))
        let headFrames = max(0, Int(keepHead / 0.02))
        let tailFrames = max(0, Int(keepTail / 0.02))

        // 任一段（首 / 尾 / 中间）超过它该保留的上限才动手；否则直接返回，
        // 避免无谓拷贝。开头 3 秒静音会让人点播放后干等，结尾同理，一并处理。
        var needsWork = false
        for (a, b) in runs {
            let cap: Int
            if a == 0 { cap = headFrames }
            else if b == rms.count { cap = tailFrames }
            else { cap = maxFrames }
            if (b - a) > cap { needsWork = true; break }
        }
        guard needsWork else { return samples }

        var output: [Float] = []
        output.reserveCapacity(count)
        var previous = 0
        for (a, b) in runs {
            let startSample = framesStart[a]
            let endSample = (b < framesStart.count) ? framesStart[b] : count
            let isHead = (a == 0)
            let isTail = (b == rms.count)
            let cap: Int
            if isHead { cap = headFrames }
            else if isTail { cap = tailFrames }
            else { cap = maxFrames }
            let keep = min(b - a, cap)
            let keepSamples = min(keep * frame, endSample - startSample)

            // 保留这一段之前的有声区
            if startSample > previous {
                output.append(contentsOf: samples[previous..<startSample])
            }
            // 再保留静音段的开头一小段
            if keepSamples > 0 {
                output.append(contentsOf: samples[startSample..<(startSample + keepSamples)])
            }
            previous = endSample
        }
        if previous < count {
            output.append(contentsOf: samples[previous..<count])
        }
        return output
    }

    /// 交叉淡化拼接，消除分段接缝的爆音
    static func append(_ samples: [Float], with tail: [Float], sampleRate: Double, fade: Double) -> [Float] {
        guard !tail.isEmpty else { return samples }
        guard !samples.isEmpty else { return tail }
        let fadeCount = min(Int(fade * sampleRate), min(samples.count, tail.count))
        if fadeCount <= 1 { return samples + tail }

        var output = samples
        let start = samples.count - fadeCount
        for index in 0..<fadeCount {
            let weight = Float(index) / Float(fadeCount)
            output[start + index] = samples[start + index] * (1 - weight) + tail[index] * weight
        }
        output.append(contentsOf: tail[fadeCount...])
        return output
    }
}

enum AudioAnalysis {
    static func peaks(from samples: [Float], count: Int) -> [Float] {
        guard !samples.isEmpty, count > 0 else { return [] }
        let bucket = max(1, samples.count / count)
        var result: [Float] = []
        result.reserveCapacity(count)
        var index = 0
        while index < samples.count {
            let end = min(index + bucket, samples.count)
            var maxValue: Float = 0
            for cursor in index..<end {
                maxValue = max(maxValue, abs(samples[cursor]))
            }
            result.append(maxValue)
            index = end
        }
        let peak = result.max() ?? 0
        if peak > 0.0001 {
            result = result.map { $0 / peak }
        }
        return result
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in samples { sum += Double(sample * sample) }
        return Float((sum / Double(samples.count)).squareRoot())
    }

    static func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// 简化信噪比：分帧 RMS 的 90 分位 / 10 分位
    static func snrDB(_ samples: [Float], sampleRate: Double) -> Double {
        let frame = max(1, Int(sampleRate * 0.02))
        guard samples.count > frame * 4 else { return 0 }
        var values: [Float] = []
        var index = 0
        while index + frame <= samples.count {
            var sum: Double = 0
            for cursor in index..<(index + frame) {
                sum += Double(samples[cursor] * samples[cursor])
            }
            values.append(Float((sum / Double(frame)).squareRoot()))
            index += frame
        }
        guard values.count > 4 else { return 0 }
        values.sort()
        let noise = max(values[values.count / 10], 0.00005)
        let signal = max(values[min(values.count - 1, values.count * 9 / 10)], noise)
        return max(0, 20 * log10(Double(signal / noise)))
    }

    /// 自相关基频估计（Hz），用于克隆声纹的音高参数
    static func estimatePitch(_ samples: [Float], sampleRate: Double) -> Double? {
        guard samples.count > 1024, sampleRate > 0 else { return nil }
        let windowLength = min(4096, samples.count)
        let start = max(0, samples.count / 2 - windowLength / 2)
        let window = Array(samples[start..<(start + windowLength)])

        var mean: Float = 0
        for value in window { mean += value }
        mean /= Float(window.count)
        var centered = window.map { $0 - mean }

        // 汉宁窗，抑制边界泄漏
        for index in 0..<centered.count {
            let weight = 0.5 - 0.5 * cos(2 * .pi * Float(index) / Float(centered.count - 1))
            centered[index] *= weight
        }

        let minLag = max(2, Int(sampleRate / 400))
        let maxLag = min(centered.count / 2, Int(sampleRate / 60))
        guard maxLag > minLag else { return nil }

        var bestLag = 0
        var bestScore: Float = 0
        for lag in minLag...maxLag {
            var correlation: Float = 0
            var energy: Float = 0
            var index = 0
            while index + lag < centered.count {
                correlation += centered[index] * centered[index + lag]
                energy += centered[index + lag] * centered[index + lag]
                index += 1
            }
            let score = energy > 0 ? correlation / energy.squareRoot() : 0
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0, bestScore > 0.15 else { return nil }
        return sampleRate / Double(bestLag)
    }

    /// 过零率映射出的明亮度 0~1
    static func brightness(_ samples: [Float], sampleRate: Double) -> Double {
        guard samples.count > 32 else { return 0.5 }
        var crossings = 0
        for index in 1..<samples.count where (samples[index - 1] < 0) != (samples[index] < 0) {
            crossings += 1
        }
        let zcr = Double(crossings) / Double(samples.count)
        return min(1, max(0, zcr / 0.22))
    }

    /// 有声帧占比，用于估算有效语音时长
    static func speechRatio(_ samples: [Float], sampleRate: Double) -> Double {
        let frame = max(1, Int(sampleRate * 0.02))
        guard samples.count > frame else { return 0 }
        var voiced = 0
        var total = 0
        var index = 0
        while index + frame <= samples.count {
            var sum: Double = 0
            for cursor in index..<(index + frame) {
                sum += Double(samples[cursor] * samples[cursor])
            }
            let value = (sum / Double(frame)).squareRoot()
            if value > 0.012 { voiced += 1 }
            total += 1
            index += frame
        }
        guard total > 0 else { return 0 }
        return Double(voiced) / Double(total)
    }
}
