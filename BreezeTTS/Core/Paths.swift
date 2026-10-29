import AppKit
import Foundation

/// Every on-disk location the app touches. The app is not sandboxed, so these
/// live under `~/Library/Application Support/<folderName>`.
///
/// 精简版和完整版必须各用各的目录，否则两个 App 会共用模型、音色和历史，
/// 装在一起时互相污染，也没法模拟「新用户第一次打开」。
enum Paths {
    static let folderName: String = {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.hasSuffix(".lite") ? "BreezeTTS Lite" : "BreezeTTS"
    }()

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    static var models: URL { appSupport.appendingPathComponent("models", isDirectory: true) }
    static var exports: URL { appSupport.appendingPathComponent("exports", isDirectory: true) }
    static var voices: URL { appSupport.appendingPathComponent("voices", isDirectory: true) }
    static var recordings: URL { appSupport.appendingPathComponent("recordings", isDirectory: true) }
    /// Scratch space for the file the transport plays when an export failed.
    static var cache: URL { appSupport.appendingPathComponent("cache", isDirectory: true) }

    static var historyFile: URL { appSupport.appendingPathComponent("history.json") }
    static var voicesFile: URL { appSupport.appendingPathComponent("voices.json") }

    static var defaultModelDirectory: URL { models }

    @discardableResult
    static func ensureDirectories() -> Bool {
        let fm = FileManager.default
        for url in [appSupport, models, exports, voices, recordings, cache] {
            if !fm.fileExists(atPath: url.path) {
                do {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                } catch {
                    NSLog("BreezeTTS: cannot create \(url.path): \(error.localizedDescription)")
                    return false
                }
            }
        }
        return true
    }

    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension Int64 {
    var humanBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: self)
    }

    var humanGB: String {
        String(format: "%.1f GB", Double(self) / 1_073_741_824.0)
    }
}
