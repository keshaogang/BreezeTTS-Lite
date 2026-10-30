//
//  GenerationEstimator.swift
//  BreezeSpeak
//
//  生成耗时估算：核心是「实时率」—— 生成 1 秒音频需要计算几秒。
//  实时率来自引擎每次推理的实测值（音频时长 ÷ 墙钟耗时），按权重档位分别记录，
//  多次结果做指数平滑，避免单次波动把估算带偏。
//
//  估算公式：音频时长（按语速估）÷ 实时率，权重还没加载时另加冷启动加载时间。
//  全程本地，只存 UserDefaults，无任何上报。
//

import Foundation

enum GenerationEstimator {

    private static let factorKey = "breezespeak.estimator.realtimeFactor"
    private static let loadKey = "breezespeak.estimator.loadSeconds"

    // MARK: 基线

    /// 没有实测值时的起点。
    /// 真机 M3 + Metal + Q8_0 实测 ≈ 0.10x 实时；模拟器走 CPU 后端，慢一个数量级。
    private static var baselineRealtimeFactor: Double {
        #if targetEnvironment(simulator)
        return 0.015
        #else
        return 0.10
        #endif
    }

    /// 冷启动加载基线（mmap 命中时实测 ~3s，首装冷读 ~18s，取中间值）
    private static let baselineLoadSeconds: Double = 8

    // MARK: 读取

    static func realtimeFactor(for tierID: String) -> Double {
        let table = UserDefaults.standard.dictionary(forKey: factorKey) as? [String: Double]
        guard let value = table?[tierID], value.isFinite, value > 0.001 else {
            return baselineRealtimeFactor
        }
        return value
    }

    static func loadSeconds(for tierID: String) -> Double {
        let table = UserDefaults.standard.dictionary(forKey: loadKey) as? [String: Double]
        guard let value = table?[tierID], value.isFinite, value > 0 else {
            return baselineLoadSeconds
        }
        return value
    }

    // MARK: 记录

    static func record(realtimeFactor: Double, tierID: String) {
        guard realtimeFactor.isFinite, realtimeFactor > 0.001, realtimeFactor < 100 else { return }
        var table = (UserDefaults.standard.dictionary(forKey: factorKey) as? [String: Double]) ?? [:]
        let smoothed = table[tierID].map { $0 * 0.6 + realtimeFactor * 0.4 } ?? realtimeFactor
        table[tierID] = smoothed
        UserDefaults.standard.set(table, forKey: factorKey)
    }

    static func record(loadSeconds: Double, tierID: String) {
        guard loadSeconds.isFinite, loadSeconds > 0, loadSeconds < 600 else { return }
        var table = (UserDefaults.standard.dictionary(forKey: loadKey) as? [String: Double]) ?? [:]
        let smoothed = table[tierID].map { $0 * 0.5 + loadSeconds * 0.5 } ?? loadSeconds
        table[tierID] = smoothed
        UserDefaults.standard.set(table, forKey: loadKey)
    }

    // MARK: 估算

    /// 预计生成耗时（秒）
    static func estimate(text: String, tierID: String, modelLoaded: Bool) -> Double {
        let speech = TextSegmenter.estimatedSpeechSeconds(text)
        var total = speech / realtimeFactor(for: tierID)
        if !modelLoaded { total += loadSeconds(for: tierID) }
        return total
    }

    /// 「约 35 秒」/「约 2 分 30 秒」
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        if seconds < 95 {
            return String(format: "约 %.0f 秒", seconds.rounded())
        }
        let total = Int(seconds.rounded())
        return String(format: "约 %d 分 %02d 秒", total / 60, total % 60)
    }
}
