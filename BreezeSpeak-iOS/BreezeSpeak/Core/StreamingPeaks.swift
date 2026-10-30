//
//  StreamingPeaks.swift
//  BreezeSpeak
//
//  流式波形的增量累积器。
//
//  为什么需要它：生成过程中音频是一段一段回传的，如果每次刷新 UI 都把「到目前的
//  全部采样」重新算一遍峰值，长音频就变成 O(n²) —— 每段刷新都要复制并遍历几百万
//  个 float，既吃满内存带宽又抢推理的时间。
//
//  这里每个采样只被处理一次：进桶时取绝对值最大值，桶满了就封存；
//  桶数超过上限时两两合并（分辨率减半），保持内存与刷新开销恒定。
//

import Foundation

final class IncrementalPeaks {
    /// 初始桶容量（采样数）。24 kHz 下约 21 ms
    private let baseBucketSize: Int
    private let maxBuckets: Int

    private let lock = NSLock()
    private var bucketSize: Int
    private var sealed: [Float] = []      // 已封存的桶
    private var currentPeak: Float = 0   // 当前桶的峰值
    private var currentCount = 0         // 当前桶已收的采样数
    private var totalSamples = 0

    init(baseBucketSize: Int = 512, maxBuckets: Int = 720) {
        self.baseBucketSize = baseBucketSize
        self.bucketSize = baseBucketSize
        self.maxBuckets = maxBuckets
        sealed.reserveCapacity(maxBuckets)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        sealed.removeAll(keepingCapacity: true)
        bucketSize = baseBucketSize
        currentPeak = 0
        currentCount = 0
        totalSamples = 0
    }

    /// 追加连续数组。引擎线程调用，复杂度只与 chunk 长度有关。
    func append(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var index = 0
        let count = chunk.count
        while index < count {
            let remaining = bucketSize - currentCount
            let take = min(remaining, count - index)
            var peak = currentPeak
            var i = index
            let end = index + take
            while i < end {
                let magnitude = abs(chunk[i])
                if magnitude > peak { peak = magnitude }
                i += 1
            }
            currentPeak = peak
            currentCount += take
            totalSamples += take
            index = end
            if currentCount >= bucketSize { sealLocked() }
        }
    }

    /// 追加未初始化内存里的采样（避免为引擎回传的数据再建一份数组）
    func append(contentsOf buffer: UnsafeBufferPointer<Float>) {
        guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var index = 0
        let count = buffer.count
        while index < count {
            let take = min(bucketSize - currentCount, count - index)
            var peak = currentPeak
            var i = index
            let end = index + take
            while i < end {
                let magnitude = abs(base[i])
                if magnitude > peak { peak = magnitude }
                i += 1
            }
            currentPeak = peak
            currentCount += take
            totalSamples += take
            index = end
            if currentCount >= bucketSize { sealLocked() }
        }
    }

    /// 桶封存；桶数超上限时两两合并，分辨率降一半
    private func sealLocked() {
        guard currentCount > 0 else { return }
        sealed.append(currentPeak)
        currentPeak = 0
        currentCount = 0
        if sealed.count > maxBuckets {
            var merged = [Float]()
            merged.reserveCapacity(maxBuckets)
            var index = 0
            while index < sealed.count {
                let second = index + 1 < sealed.count ? sealed[index + 1] : sealed[index]
                merged.append(max(sealed[index], second))
                index += 2
            }
            sealed = merged
            bucketSize *= 2
        }
    }

    /// 取出 bars 根柱子的波形（取各区间的最大值）。只在刷新 UI 时调用。
    func snapshot(bars: Int = 120) -> [Float] {
        lock.lock()
        var source = sealed
        if currentCount > 0 { source.append(currentPeak) }
        lock.unlock()

        guard bars > 0 else { return [] }
        guard !source.isEmpty else { return [Float](repeating: 0, count: bars) }

        var output = [Float]()
        output.reserveCapacity(bars)
        for bar in 0..<bars {
            let start = bar * source.count / bars
            let end = max(start + 1, (bar + 1) * source.count / bars)
            var peak: Float = 0
            var i = start
            while i < end && i < source.count {
                if source[i] > peak { peak = source[i] }
                i += 1
            }
            output.append(peak)
        }
        return output
    }

    /// 已收到的采样总数（用于进度兜底估算）
    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return totalSamples
    }
}
