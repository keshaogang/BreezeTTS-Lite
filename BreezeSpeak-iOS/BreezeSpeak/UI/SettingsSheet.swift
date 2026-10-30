//
//  SettingsSheet.swift
//  BreezeSpeak
//
//  播放与合成参数、数据位置、引擎信息。
//  视觉语言与 macOS 版设置面板一致。
//

import SwiftUI
import UIKit

struct SettingsSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vm: SynthesisViewModel
    @ObservedObject private var glass = GlassSettings.shared

    var body: some View {
        SheetChrome(title: "设置",
                    subtitle: "参数只影响本机生成，不会被上传") {
            VStack(alignment: .leading, spacing: 22) {
                playbackSection
                inputSection
                appearanceSection
                synthSection
                memorySection
                dataSection
                integrationSection
                aboutSection
            }
        }
    }

    // MARK: - 系统集成

    private var integrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "快捷指令与小组件")

            KeyValueRow(key: "快捷指令", value: "快捷指令 App 里搜 BreezeSpeak")
            KeyValueRow(key: "桌面小组件", value: "长按桌面 → 左上角 + → 搜 BreezeSpeak")
            KeyValueRow(key: "锁屏小组件", value: "长按锁屏 → 自定义 → 添加小组件")

            Text("快捷指令可直接拿到合成的 WAV 文件，能接着串「保存到文件」「播放」「隔空投送」。小组件上的每个入口都会直接跳到对应界面。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openShortcutsApp()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("打开快捷指令 App")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    private func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 外观

    @ViewBuilder
    private var appearanceSection: some View {
        if #available(iOS 26.0, *) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "外观")

                toggle("液态玻璃",
                       detail: "开启后工具栏与弹窗用系统的玻璃材质，能透出底下的内容；关闭则退回毛玻璃，更实、更安静。",
                       isOn: Binding(
                           get: { glass.enabled },
                           set: { glass.enabled = $0 }
                       ))
            }
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "播放")

            toggle("生成后自动播放", detail: "关闭则只在生成结束时刷新波形与时长",
                   isOn: $vm.autoPlay)

            slider("播放速度", value: Binding(
                get: { env.player.playbackRate },
                set: { env.player.playbackRate = $0 }
            ), range: 0.75...1.5, step: 0.05, hint: "只影响回放，不改变导出文件")
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "输入")

            toggle("回车键发送生成",
                   detail: "开启后，在正文里敲回车就等于点「生成」，正文里的换行会被吃掉一个；写长段落、要保留换行时关掉它。",
                   isOn: $vm.submitOnReturn)
        }
    }

    private var synthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "合成")

            slider("全局语速", value: $vm.speed, range: 0.7...1.3, step: 0.05,
                   hint: "0.7 偏慢 · 1.05 自然 · 1.3 偏快")
            slider("指导强度 cfg_scale", value: $vm.guidanceScale,
                   range: AppConfig.guidanceRange, step: 0.1,
                   hint: "1.0 自然 · 2~3 让 [笑] / (cough) 这类标记真正生效 · 超过 3 开始发刺")

            toggle("锁定音色",
                   detail: "开启后：① 采样改成逐帧贪心，同一段文字重复生成逐样本一致；② 每条声线第一次出声时会先用一句固定的话把音色钉成参考音频，之后都按这段参考克隆——换任何文字听起来都是同一个人。关闭会回到权重自带的温度采样，每次呼吸、音高、音色都可能不一样。",
                   isOn: $vm.lockVoice)

            HStack(spacing: 8) {
                Button {
                    vm.reanchorCurrentVoice()
                } label: {
                    Label("重新固定音色", systemImage: "waveform.badge.plus")
                }
                .quietPill()
                .disabled(!vm.lockVoice || vm.effectiveVoice.kind == .clone)

                Spacer(minLength: 0)
            }

            KeyValueRow(key: "长文本切分", value: "引擎内部分段 · 约 600 字 / 段")
            KeyValueRow(key: "采样率", value: "\(Int(AppConfig.sampleRate)) Hz · \(AppConfig.bitDepth) bit")

            if let result = vm.lastResult, vm.lastElapsed > 0 {
                let ratio = result.duration / vm.lastElapsed
                KeyValueRow(key: "上次生成",
                            value: "\(String(format: "%.1f", result.duration)) 秒音频 / 耗时 \(String(format: "%.1f", vm.lastElapsed)) 秒 · \(String(format: "%.2f", ratio))× 实时")
            }
        }
    }

    // MARK: - 内存

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "内存",
                         trailing: AnyView(Pill(text: env.memory.pressureLabel)))

            KeyValueRow(key: "进程占用", value: TimeFormat.bytes(Int64(env.memory.footprint)))
            KeyValueRow(key: "系统余量",
                        value: env.memory.available > 0 ? TimeFormat.bytes(Int64(env.memory.available)) : "—")
            KeyValueRow(key: "权重",
                        value: BreezeEngineCore.shared.isLoaded
                            ? "常驻内存 · 可连续生成，不必重新加载"
                            : "未加载 · 下次生成会加载")

            toggle("生成后释放模型内存",
                   detail: "开启后每次生成收尾就把权重还给系统，进程占用立刻降下来；代价是下次生成要重新加载（真机约 3 秒，首次安装约 17 秒）。默认关闭——留住权重才能连续快速生成。",
                   isOn: $vm.releaseModelAfterRun)

            HStack(spacing: 8) {
                Button {
                    env.runtime.unloadAll()
                    env.memory.sample()
                    vm.showToast("已释放模型权重，下次生成会重新加载")
                } label: {
                    Label("立即释放权重", systemImage: "memorychip")
                }
                .quietPill()
                .disabled(!BreezeEngineCore.shared.isLoaded)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "数据位置")

            KeyValueRow(key: "模型", value: shortPath(AppPaths.modelDirectory))
            KeyValueRow(key: "音频", value: shortPath(AppPaths.audioDirectory))
            KeyValueRow(key: "导出", value: shortPath(AppPaths.exportDirectory))
            KeyValueRow(key: "声纹", value: shortPath(AppPaths.embeddingsDirectory))
            KeyValueRow(key: "音频缓存", value: "\(AudioCache.count) 条 · \(TimeFormat.bytes(AudioCache.sizeBytes))")

            Text("全部位于 App 沙盒内。已开启文件共享，可在「文件」App 的「我的 iPad → BreezeSpeak」里查看导出的 WAV。\n同一段文字配同一条声线再次生成会直接复用缓存（听感完全一致，且不耗推理时间）；清掉缓存后会用新的随机采样重新生成。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    vm.saveToDocumentsFolder()
                } label: {
                    Label("保存当前音频到「文件」", systemImage: "folder.badge.plus")
                }
                .quietPill()
                .disabled(vm.lastResult == nil)

                Button {
                    AudioCache.clear()
                    vm.showToast("已清空音频缓存")
                } label: {
                    Label("清空音频缓存", systemImage: "trash")
                }
                .quietPill()

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "关于")
            KeyValueRow(key: "引擎", value: vm.engineLabel)
            KeyValueRow(key: "权重", value: "\(env.model.selectedTier.shortName) · \(TimeFormat.bytes(env.model.totalBytes))")
            KeyValueRow(key: "推理核心", value: "Breeze-TTS-2 C++ · ggml · \(InferenceBackend.label)")
            KeyValueRow(key: "版本", value: "1.0 (1)")

            if !vm.isNeural {
                Text(vm.engineNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("BreezeSpeak · iPadOS 16+ · Apple Silicon iPad · 无登录、无广告、无联网上报")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    /// 沙盒绝对路径太长，只保留可读的那一段
    private func shortPath(_ url: URL) -> String {
        let path = url.path
        for marker in ["/Documents/", "/Library/Application Support/"] {
            if let range = path.range(of: marker) {
                let tail = String(path[range.upperBound...])
                return "…" + marker + tail
            }
        }
        return url.lastPathComponent
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        // 不用系统开关 + tint(.primary)：深色下轨道与滑块都变白，整块糊成一片。
        .toggleStyle(InkSwitchToggleStyle())
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).tint(Theme.controlTint)
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
