//
//  ModelManager.swift
//  BreezeSpeak
//
//  GGUF 权重全生命周期：档位选择、断点续传下载、体积极校验、缓存清理。
//  权重与 macOS 版完全同源（HoppouAI/Breeze-TTS-2.cpp 的 GGUF），
//  只是换了推理后端：桌面是 Vulkan/Metal，这里是 iOS 的 Metal。
//

import Foundation
import SwiftUI

// MARK: - 档位定义

struct ModelTier: Identifiable, Hashable {
    let id: String
    let fileName: String
    let name: String
    let shortName: String
    /// 文件精确字节数，用来判断下载是否完整
    let bytes: Int64
    /// 推理时的峰值工作集估算（权重 + KV + Metal 缓冲）
    let peakBytes: UInt64
    /// 是否为低内存设备的推荐档（默认就是最小的 q4_k）
    let recommendedOnLowRAM: Bool
    let summary: String
    let note: String

    var fileURL: URL { AppPaths.modelDirectory.appendingPathComponent(fileName) }

    var installed: Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        return AppPaths.bytes(at: fileURL) == bytes
    }

    var partialBytes: Int64 {
        min(AppPaths.bytes(at: fileURL), bytes)
    }
}

enum ModelTiers {
    static let gigabyte: UInt64 = 1_073_741_824

    /// iPad 上暴露三档，任何设备都可以选；小内存设备默认落在最小的 q4_k。
    static let all: [ModelTier] = [
        ModelTier(
            id: "q4_k",
            fileName: "breeze-tts-2-q4_k.gguf",
            name: "Q4_K · 省内存",
            shortName: "Q4_K",
            bytes: 2_538_909_376,
            peakBytes: 3_221_225_472,
            recommendedOnLowRAM: true,
            summary: "2.4 GB 文件 · 峰值约 3.0 GB",
            note: "默认档。语气细节略降一点，但加载快、长时间朗读也稳，8 GB 的 iPad 首选。"
        ),
        ModelTier(
            id: "q6_k",
            fileName: "breeze-tts-2-q6_k.gguf",
            name: "Q6_K · 中档",
            shortName: "Q6_K",
            bytes: 3_069_969_664,
            peakBytes: 3_758_096_384,
            recommendedOnLowRAM: false,
            summary: "2.9 GB 文件 · 峰值约 3.5 GB",
            note: "音质与体积的折中。8 GB 的 iPad 也能跑，只是加载更慢、后台更容易被回收。"
        ),
        ModelTier(
            id: "q8_0",
            fileName: "breeze-tts-2-q8_0.gguf",
            name: "Q8_0 · 近似无损",
            shortName: "Q8_0",
            bytes: 3_568_844_480,
            peakBytes: 4_294_967_296,
            recommendedOnLowRAM: false,
            summary: "3.3 GB 文件 · 峰值约 4.0 GB",
            note: "听感几乎等同 F16。8 GB 的 iPad 可以跑，但长文本生成时内存余量小，闪退风险自担。"
        )
    ]

    static func tier(id: String) -> ModelTier {
        all.first { $0.id == id } ?? all[0]
    }

    /// 低内存设备的推荐档：就是体积最小的那一档
    static var recommendedTierID: String {
        all.min { $0.peakBytes < $1.peakBytes }?.id ?? all[0].id
    }
}

// MARK: - 状态

enum ModelStatus: Equatable {
    case absent
    case downloading(Double)
    case verifying
    case ready
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var isReady: Bool { self == .ready }
}

// MARK: - 管理器

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var status: ModelStatus = .absent
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var speed: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var selectedTierID: String

    private var downloadTask: Task<Void, Never>?
    private var lastSampleDate = Date()
    private var lastSampleBytes: Int64 = 0
    private static let tierKey = "breezespeak.modelTier"

    init() {
        var stored = UserDefaults.standard.string(forKey: Self.tierKey) ?? AppConfig.defaultTierID
        #if DEBUG
        // 自动化 / 真机验证用：-modelTier q8_0 直接指定档位
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-modelTier"), args.count > index + 1 {
            stored = args[index + 1]
        }
        #endif

        // 默认落在最小档；用户手动选过大档就尊重用户的选择，
        // 只有用户从未设置过（stored 为 nil）时才用默认值。
        selectedTierID = ModelTiers.tier(id: stored).id
        refresh()

        // 首次安装（一份权重都没有）时自动开始下载，符合「打开即用」的产品约定
        if selectedTier.partialBytes == 0 {
            Task { [weak self] in
                self?.downloadIfNeeded()
            }
        }
    }

    // MARK: 派生

    var selectedTier: ModelTier { ModelTiers.tier(id: selectedTierID) }

    var totalBytes: Int64 { selectedTier.bytes }

    /// 只有尺寸完全一致才认为可用，避免半截文件被送进引擎
    var readyModelURL: URL? { selectedTier.installed ? selectedTier.fileURL : nil }

    var isReady: Bool { readyModelURL != nil }
    var isDownloading: Bool { status.isDownloading }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }

    var remainingBytes: Int64 { max(0, totalBytes - downloadedBytes) }

    /// 这一档是否是本设备的推荐档（低内存设备推荐最小档）
    func isRecommended(_ tier: ModelTier) -> Bool {
        tier.id == ModelTiers.recommendedTierID
    }

    /// 当前设备物理内存（供文案展示）
    var deviceRAMBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    var diskUsage: Int64 { AppPaths.directorySize(AppPaths.modelDirectory) }

    var cacheSummary: String { "模型占用 \(TimeFormat.bytes(diskUsage))" }

    var modelNumberSummary: String {
        "\(selectedTier.shortName) · \(TimeFormat.bytes(totalBytes))"
    }

    // MARK: 刷新

    func refresh() {
        if let url = readyModelURL {
            status = .ready
            downloadedBytes = totalBytes
            _ = url
        } else {
            let partial = selectedTier.partialBytes
            downloadedBytes = partial
            status = partial > 0 ? .failed("下载未完成，可继续") : .absent
        }
    }

    func select(tierID: String) {
        guard tierID != selectedTierID else { return }
        downloadTask?.cancel()
        downloadTask = nil
        selectedTierID = ModelTiers.tier(id: tierID).id
        UserDefaults.standard.set(selectedTierID, forKey: Self.tierKey)
        lastError = nil
        speed = 0
        refresh()
        downloadIfNeeded()
    }

    // MARK: 下载

    func downloadIfNeeded() {
        guard !isReady, !isDownloading else { return }
        startDownload()
    }

    func redownload() {
        downloadTask?.cancel()
        downloadTask = nil
        let target = selectedTier.fileURL
        try? FileManager.default.removeItem(at: target)
        downloadedBytes = 0
        status = .absent
        startDownload()
    }

    func startDownload() {
        guard downloadTask == nil else { return }
        lastSampleDate = Date()
        lastSampleBytes = 0
        speed = 0
        lastError = nil
        status = .downloading(progress)

        let tier = selectedTier
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.download(tier: tier)
                self.status = .verifying
                if tier.installed {
                    self.downloadedBytes = tier.bytes
                    self.status = .ready
                    Haptics.success()
                } else {
                    self.status = .failed("文件大小不符，请重新下载")
                }
            } catch is CancellationError {
                self.status = self.downloadedBytes > 0 ? .failed("下载已暂停，可继续") : .absent
            } catch {
                self.status = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
            self.downloadTask = nil
            self.speed = 0
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        speed = 0
        status = downloadedBytes > 0 ? .failed("下载已暂停，可继续") : .absent
    }

    private func download(tier: ModelTier) async throws {
        AppPaths.ensure(AppPaths.modelDirectory)
        guard let remote = URL(string: AppConfig.modelMirrorBase + "/" + tier.fileName) else {
            throw TTSError.exportFailed("下载地址无效")
        }
        try await downloadFile(remote: remote, destination: tier.fileURL, expected: tier.bytes)
    }

    /// Range 续传：已下载的字节直接跳过，中断后再点一次继续
    private func downloadFile(remote: URL, destination: URL, expected: Int64) async throws {
        var existing = AppPaths.bytes(at: destination)
        if expected > 0 && existing == expected { return }
        if existing > expected { existing = 0; DiskStore.remove(destination) }

        var request = URLRequest(url: remote)
        request.timeoutInterval = 60
        request.setValue("BreezeSpeak/1.0 (iPad)", forHTTPHeaderField: "User-Agent")
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 200
        if code == 416 { return }
        if code == 200 && existing > 0 {
            // 服务器不认 Range，只能从头来
            existing = 0
            DiskStore.remove(destination)
        }
        if code >= 400 {
            throw TTSError.exportFailed("下载被拒绝（HTTP \(code)），请检查网络后重试")
        }

        AppPaths.ensure(destination.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: destination)
        try handle.seekToEnd()
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)
        var written = existing
        var since = Date()
        var sinceBytes = written
        downloadedBytes = written

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Task.isCancelled { throw CancellationError() }

                let now = Date()
                if now.timeIntervalSince(since) > 0.4 {
                    speed = Double(written - sinceBytes) / now.timeIntervalSince(since)
                    since = now
                    sinceBytes = written
                }
                downloadedBytes = written
                status = .downloading(progress)
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        downloadedBytes = written
        status = .downloading(progress)
    }

    // MARK: 清理

    /// 只删当前档位，换档时不必重下别的
    func clearCache() {
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: selectedTier.fileURL)
        downloadedBytes = 0
        speed = 0
        status = .absent
        BreezeEngineCore.shared.unload()
    }

    /// 删光 Models 目录（设置里的「清空模型缓存」）
    func clearAllCaches() {
        downloadTask?.cancel()
        downloadTask = nil
        clearCache()
        try? FileManager.default.removeItem(at: AppPaths.modelDirectory)
        AppPaths.ensure(AppPaths.modelDirectory)
        downloadedBytes = 0
        status = .absent
    }
}
