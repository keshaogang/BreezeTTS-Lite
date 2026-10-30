//
//  ModelSheet.swift
//  BreezeSpeak
//
//  模型管理：GGUF 档位、下载进度、缓存明细、离线说明。
//  与 macOS 版共用同一份权重，只是这里按 iPad 的内存现实只保留三档。
//

import SwiftUI

struct ModelSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vm: SynthesisViewModel

    var body: some View {
        SheetChrome(title: "模型",
                    subtitle: "Breeze TTS 2 · GGUF 本地推理") {
            VStack(alignment: .leading, spacing: 22) {
                tierSection
                downloadSection
                memorySection
                cacheSection
                offlineSection
            }
        }
    }

    // MARK: - 档位

    private var tierSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "权重大小",
                         trailing: AnyView(Text(vm.engineLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)))

            VStack(spacing: 6) {
                ForEach(ModelTiers.all) { tier in
                    tierRow(tier)
                }
            }

            Text("档位之间只影响音质细节与内存占用，模型能力完全一致；换档需要重新下载对应文件。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierRow(_ tier: ModelTier) -> some View {
        let selected = tier.id == env.model.selectedTierID
        let recommended = env.model.isRecommended(tier)

        return Button {
            env.model.select(tierID: tier.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.25))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tier.name)
                            .font(.system(size: 12.5, weight: .medium))
                        if tier.installed { Pill(text: "已下载") }
                        if recommended { Pill(text: "本机推荐") }
                        Spacer(minLength: 0)
                    }
                    Text(tier.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(tier.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Theme.softFill : Theme.faintFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 下载

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "下载",
                         trailing: AnyView(Pill(text: statusLabel)))

            if env.model.isDownloading {
                bar(env.model.progress)
                HStack {
                    Text("\(Int(env.model.progress * 100))% · \(TimeFormat.bytes(env.model.downloadedBytes)) / \(TimeFormat.bytes(env.model.totalBytes))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if env.model.speed > 0 {
                        Text(String(format: "%.1f MB/s", env.model.speed / 1_048_576))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if env.model.isReady {
                bar(1)
                Text("已缓存到沙盒 · 断网、飞行模式都能推理")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                bar(env.model.progress)
                Text(env.model.downloadedBytes > 0
                     ? "下载未完成，点「继续下载」从断点接着来。"
                     : "首次使用需下载 \(TimeFormat.bytes(env.model.totalBytes))，支持断点续传。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if env.model.isDownloading {
                    Button {
                        env.model.cancelDownload()
                    } label: {
                        Label("暂停", systemImage: "pause")
                    }
                    .quietPill()
                } else if env.model.isReady {
                    Button {
                        env.model.redownload()
                    } label: {
                        Label("重新下载", systemImage: "arrow.clockwise")
                    }
                    .quietPill()
                } else {
                    Button {
                        env.model.downloadIfNeeded()
                    } label: {
                        Label(env.model.downloadedBytes > 0 ? "继续下载" : "开始下载", systemImage: "arrow.down.circle")
                    }
                    .primaryPill()
                }

                Button {
                    env.model.clearCache()
                    vm.runtime.unloadAll()
                    vm.showToast("已清空该档位权重")
                } label: {
                    Label("清空该档", systemImage: "trash")
                }
                .quietPill()

                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            if let error = env.model.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLabel: String {
        if env.model.isDownloading { return "下载中" }
        if env.model.isReady { return "就绪" }
        if env.model.downloadedBytes > 0 { return "已暂停" }
        return "未下载"
    }

    private func bar(_ value: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: max(2, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 4)
    }

    // MARK: - 内存

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "设备内存",
                         trailing: AnyView(Pill(text: env.memory.pressureLabel)))

            metric("进程占用", value: TimeFormat.bytes(Int64(env.memory.footprint)),
                   fraction: env.memory.usageFraction)
            metric("系统余量", value: env.memory.available > 0 ? TimeFormat.bytes(Int64(env.memory.available)) : "—",
                   fraction: nil)
            metric("设备物理内存", value: TimeFormat.bytes(Int64(env.memory.total)), fraction: nil)

            KeyValueRow(key: "权重状态",
                        value: BreezeEngineCore.shared.isLoaded
                            ? "常驻内存 · \(TimeFormat.bytes(Int64(env.model.selectedTier.peakBytes)))"
                            : "未加载")

            Text("「系统余量」表示离被系统杀掉还剩多少，而不是「还能不能再生成一次」。权重用 mmap 常驻时会一直计在这份配额里，所以它只剩几百 MB 是正常的——再次推理复用同一份权重，不会重复占内存，可以一直连续生成。只有系统真的发内存警告，才会自动释放权重。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    env.runtime.unloadAll()
                    env.memory.sample()
                    vm.showToast("已释放模型权重，下次生成会重新加载")
                } label: {
                    Label("释放权重内存", systemImage: "memorychip")
                }
                .quietPill()
                .disabled(!BreezeEngineCore.shared.isLoaded)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func metric(_ title: String, value: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            }
            if let fraction {
                bar(fraction)
            }
        }
    }

    // MARK: - 缓存

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "缓存与数据")

            KeyValueRow(key: "模型权重", value: TimeFormat.bytes(env.model.diskUsage))
            KeyValueRow(key: "音频历史", value: "\(env.history.items.count) 条 · \(historyBytes)")
            KeyValueRow(key: "声线声纹", value: "\(env.voices.customVoices.count) 条 · \(embeddingBytes)")

            HStack(spacing: 8) {
                Button {
                    env.history.clearAll()
                    vm.showToast("已清空历史记录")
                } label: {
                    Label("清空历史", systemImage: "clock.arrow.circlepath")
                }
                .quietPill()

                Button {
                    env.model.clearAllCaches()
                    vm.runtime.unloadAll()
                    vm.showToast("已清空全部模型缓存")
                } label: {
                    Label("清空全部权重", systemImage: "trash")
                }
                .quietPill()
            }
            .padding(.top, 2)
        }
    }

    private var historyBytes: String {
        var total: Int64 = 0
        for item in env.history.items {
            let attributes = try? FileManager.default.attributesOfItem(atPath: item.fileURL.path)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        return TimeFormat.bytes(total)
    }

    private var embeddingBytes: String {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.embeddingsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        var total: Int64 = 0
        for url in items {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return TimeFormat.bytes(total)
    }

    // MARK: - 离线说明

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "离线说明")
            bullet("权重与 macOS 版完全同源，推理走 ggml + Metal，全程不联网。")
            bullet("下载完成后可断网使用；所有数据都在 App 沙盒，卸载才会清除。")
            bullet("长文本由引擎内部按句切分流式合成，一段一段地回传音频。")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
