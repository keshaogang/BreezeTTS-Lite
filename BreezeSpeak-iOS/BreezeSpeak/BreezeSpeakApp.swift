//
//  BreezeSpeakApp.swift
//  BreezeSpeak
//
//  独立 iPad SwiftUI 离线 TTS。仅 Apple Silicon iPad · iPadOS 16+。
//

import SwiftUI

@main
struct BreezeSpeakApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase
    /// 引导是否已走完。存在 App 层，走完那一刻整棵树换成交互界面。
    @State private var onboarded = OnboardingState.isCompleted

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded {
                    RootView()
                        .transition(.opacity.combined(with: .scale(scale: 1.01)))
                } else {
                    // 协议已经同意过就从中断的下一步接着走
                    OnboardingFlow(startStep: OnboardingState.hasAcceptedDisclaimer ? 2 : 0) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            onboarded = true
                        }
                        environment.model.downloadIfNeeded()
                        environment.warmUp()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .environmentObject(environment)
            .environmentObject(environment.viewModel)
            .environmentObject(environment.voices)
            .environmentObject(environment.model)
            .environmentObject(environment.history)
            .environmentObject(environment.player)
            .environmentObject(environment.memory)
            .tint(Palette.accent)
            // 内容区之外（键盘上方、窗口拉伸时）不留白：先铺一层画布色，再把窗口底色也刷同色
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas.ignoresSafeArea())
            .canvasWindowBackground()
            .onChangeCompat(of: scenePhase) { _, newPhase in
                environment.handleScenePhase(newPhase)
                // 控制中心按钮 / 快捷指令是先把落点写下来再把 App 拉到前台，
                // 通知可能在界面还没起来时就发了，所以回到前台再取一次。
                if newPhase == .active {
                    environment.consumePendingRoute()
                }
            }
            // 小组件与快捷指令的深链：breezespeak://compose|voices|history|settings
            .onOpenURL { url in
                guard let link = WidgetLink.parse(url) else { return }
                // 引导还没走完时不跳转，否则用户会被扔进一个弹窗、看不到协议
                guard onboarded else { return }
                environment.open(link)
            }
            .task {
                environment.consumePendingRoute()
                #if DEBUG
                if OnboardingShot.requested {
                    OnboardingShot.capture(env: environment)
                } else if WidgetShot.requested {
                    WidgetShot.capture()
                } else if KBSnap.requested {
                    KBSnap.run()
                } else {
                    DebugHarness.run(env: environment)
                }
                #endif
            }
        }
    }
}
