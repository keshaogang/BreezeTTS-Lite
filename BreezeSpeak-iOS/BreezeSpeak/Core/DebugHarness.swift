//
//  DebugHarness.swift
//  BreezeSpeak
//
//  仅 DEBUG：通过启动参数驱动界面，用于自动化截图 / 走查流程。
//  例：xcrun simctl launch <device> com.breezespeak.app -demo generate
//  发布构建不包含任何相关代码。
//

#if DEBUG
import SwiftUI

enum DebugHarness {
    static var action: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demo"), args.count > index + 1 else { return nil }
        return args[index + 1]
    }

    /// 声线库默认打开的 Tab（library / library-clone / library-design）
    static var voiceTab: VoiceSheet.LabTab {
        switch action {
        case "library-clone": return .clone
        case "library-design", "design-draft", "design-save": return .design
        default: return .builtin
        }
    }

    /// 声线库内的自动化：造声 → 试听 → 保存
    static func autopilot(in lab: VoiceLabModel, dismiss: @escaping () -> Void) {
        guard let action, action.hasPrefix("design") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            lab.designDescription = "三十岁女性，中低音，略带沙哑，气息偏弱，深夜电台感"
            lab.designGuidance = 4.6
            lab.designName = "深夜电台"
            await lab.createDesign()
            if action == "design-save" {
                _ = lab.saveDraftDesign()
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            }
        }
    }

    /// 等生成真正结束（最多 90 秒），避免靠固定睡眠撞运气
    @MainActor
    private static func waitForAudio(_ env: AppEnvironment, cancellable: Bool = false) async {
        for _ in 0..<180 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if cancellable && env.viewModel.alert != nil { return }
            if env.viewModel.lastResult != nil { return }
        }
    }

    /// 在根视图出现后按参数触发一次自动化流程
    static func run(env: AppEnvironment) {
        guard let action else { return }
        Task { @MainActor in
            // route-xxx：完整走一遍「控制中心 / 快捷指令投递落点」的路径，
            // 也就是 BreezeRouter.deliver → 通知 / UserDefaults → AppEnvironment 消费。
            if action.hasPrefix("route-") {
                let raw = String(action.dropFirst("route-".count))
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if let route = BreezeRoute(rawValue: raw) {
                    BreezeRouter.deliver(route)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if env.viewModel.text.isEmpty {
                env.viewModel.text = "提醒，| 定时任务已经到时间。"
            }
            switch action {
            case "generate", "compact-generate":
                env.viewModel.generate()
            case "generate-twice":
                // 连续生成两次：专门验证「第二次必然报内存不足」是否真的修好了。
                // 如果还误报，第二次会停在 alert 上、lastResult 保持 nil。
                env.viewModel.generate()
                await waitForAudio(env, cancellable: true)
                guard env.viewModel.alert == nil else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                env.viewModel.text = "第二次连续生成，用来验证内存误报是否已经修好。"
                env.viewModel.generate()
                await waitForAudio(env, cancellable: true)
            case "library", "library-clone", "library-design", "design-draft", "design-save":
                env.viewModel.showVoiceLibrary = true
            case "models":
                env.viewModel.showModelSheet = true
            case "download":
                // 配合 -modelTier q4_k：断点续传当前档位
                env.model.downloadIfNeeded()
            case "history-sheet":
                env.viewModel.showHistory = true
            case "settings":
                env.viewModel.showSettings = true
            case "export":
                env.viewModel.generate()
                await waitForAudio(env)
                env.viewModel.exportWAV()
            case "save-files":
                env.viewModel.generate()
                await waitForAudio(env)
                env.viewModel.saveToDocumentsFolder()
            case "clear-text":
                env.viewModel.clearText()
            case "clone-record":
                // 走一遍「录音 → 转写 → 提取 → 试听」，用来验证参考音频落盘与试听链路
                env.viewModel.showVoiceLibrary = true
            case "voice-edit":
                // 直接展开当前声线的编辑器，用于截图走查
                env.viewModel.showVoiceLibrary = true
            case "focus-editor":
                // 只是让正文拿到焦点，键盘布局交给 MainSurface 自己处理
                break
            default:
                break
            }
        }
    }
}
#endif
