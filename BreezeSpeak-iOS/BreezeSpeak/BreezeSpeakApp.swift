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
            }
            .task {
                #if DEBUG
                if OnboardingShot.requested {
                    OnboardingShot.capture(env: environment)
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
