//
//  AppEnvironment.swift
//  BreezeSpeak
//

import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppEnvironment: ObservableObject {
    let voices: VoiceStore
    let model: ModelManager
    let memory: MemoryMonitor
    let history: HistoryStore
    let player: AudioPlayerController
    let runtime: SpeechRuntime
    let viewModel: SynthesisViewModel

    init() {
        let voices = VoiceStore()
        let model = ModelManager()
        let memory = MemoryMonitor()
        let history = HistoryStore()
        let player = AudioPlayerController()
        let runtime = SpeechRuntime(model: model)

        self.voices = voices
        self.model = model
        self.memory = memory
        self.history = history
        self.player = player
        self.runtime = runtime
        self.viewModel = SynthesisViewModel(
            voices: voices,
            model: model,
            memory: memory,
            history: history,
            player: player,
            runtime: runtime
        )

        memory.start()
        // memory 是独立的 ObservableObject，只有把它的变更转发出来，
        // 内存面板（模型页 / 设置页）才能每秒刷新，卸载权重后数值才会立刻掉下来。
        memoryCancellable = memory.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // 系统内存警告 = jetsam 之前的最后一次提醒。这时主动把权重还给系统，
        // 比等它把进程杀掉（表现为闪退）要好得多。
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMemoryWarning() }
        }
        // 首次启动先让用户把引导与协议读完，这里不抢跑网络：
        // 权重由引导里的「选择模型」那一步发起下载。
        if OnboardingState.isCompleted {
            model.downloadIfNeeded()
            // 权重已在本地时直接预热，第一次点生成不用再等加载
            warmUp()
        }
    }

    private var memoryCancellable: AnyCancellable?
    private var memoryWarningObserver: NSObjectProtocol?

    // MARK: - 内存压力

    private func handleMemoryWarning() {
        // 权重常驻时收到内存警告，说明系统余量已经很薄，先释放权重。
        guard runtime.isEngineLoaded else {
            memory.sample()
            return
        }
        runtime.unloadAll()
        memory.sample()
        viewModel.showToast("系统内存紧张，已释放模型权重（下次生成会自动重新加载）")
    }

    // MARK: - 预热

    /// 权重就绪就把引擎装好。失败静默（下次生成时会自动再试）。
    func warmUp() {
        Task { [weak self] in
            await self?.runtime.warmUpIfNeeded()
        }
    }

    // MARK: - 前后台

    private var pendingUnload: DispatchWorkItem?

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            memory.stop()
            runtime.trimMemory()
            // 不要一进后台就卸权重：权重是 mmap 进来的，系统在内存紧张时会自动回收
            // 文件映射页，不会因此杀进程；真正卸掉会导致切回来后再等十来秒重新加载。
            // 只有长时间停留在后台（60 秒）才彻底释放。
            scheduleDeferredUnload()
        case .active:
            pendingUnload?.cancel()
            pendingUnload = nil
            memory.start()
            runtime.refresh()
            warmUp()
        default:
            break
        }
    }

    private func scheduleDeferredUnload() {
        pendingUnload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.runtime.unloadAll() }
        }
        pendingUnload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }
}
