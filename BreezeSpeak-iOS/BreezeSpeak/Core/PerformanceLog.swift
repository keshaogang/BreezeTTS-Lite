//
//  PerformanceLog.swift
//  BreezeSpeak
//
//  每次推理的真实速度流水。写在「文件」App 可见的目录里，
//  用来确认 Metal 后端是否真的生效、以及各档位的实时率。
//
//  为什么需要它：引擎是预编译的闭源静态库，Metal 初始化失败会静默回退 CPU，
//  从 App 界面上完全看不出来（速度差 5~10 倍）。有了这份日志，
//  拿 `-cpuEngine` 跑一次、正常跑一次，对比两行数字就能确认。
//

import Foundation

enum PerformanceLog {
    struct Entry {
        var timestamp: Date
        var backend: String      // GPU / CPU（请求值，引擎静默回退查不到真相）
        var tier: String         // 实际送进引擎的权重文件名，用来排除档位与文件不匹配
        var audioSeconds: Double
        var elapsed: Double
        var characters: Int

        var realtimeFactor: Double { audioSeconds / max(elapsed, 0.001) }

        var line: String {
            let stamp = ISO8601DateFormatter().string(from: timestamp)
            // 缓存命中没有推理耗时，实时率没有意义，单独成句
            if backend == "缓存命中" {
                return String(format: "%@ | 缓存命中 | %@ | 音频 %.2fs | 直接复用，未推理 | %d 字",
                              stamp, tier, audioSeconds, characters)
            }
            return String(
                format: "%@ | %@ | %@ | 音频 %.2fs | 耗时 %.2fs | %.3fx 实时 | %d 字",
                stamp, backend, tier, audioSeconds, elapsed, realtimeFactor, characters
            )
        }
    }

    /// 失败也要落盘。
    ///
    /// 之前生成失败只弹一个 Alert，关掉就没了——用户报「长文本失败了」时，
    /// 设备上一点痕迹都不留，只能靠猜。这里把错误原文和输入规模写进同一份日志，
    /// 下次直接 `devicectl` 取回就能看到是内存、还是引擎返回的错。
    static func recordFailure(_ message: String, characters: Int, detail: String = "-") {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = String(format: "%@ | 生成失败 | %d 字 | %@ | %@",
                          stamp, characters, message, detail)
        NSLog("BreezeSpeak 失败: %@", line)
        write(line)
    }

    static func record(backend: String, tier: String,
                       audioSeconds: Double, elapsed: Double, characters: Int) {
        let entry = Entry(timestamp: Date(), backend: backend, tier: tier,
                          audioSeconds: audioSeconds, elapsed: elapsed,
                          characters: characters)
        NSLog("BreezeSpeak 性能: %@", entry.line)
        write(entry.line)
    }

    private static func write(_ line: String) {
        let url = AppPaths.performanceLogFile
        AppPaths.ensure(url.deletingLastPathComponent())
        let payload = line + "\n"
        guard let data = payload.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
        // 只留最近 200 行，别让它无限长
        trim(to: 200, at: url)
    }

    private static func trim(to limit: Int, at url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count > limit else { return }
        lines = Array(lines.suffix(limit))
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
