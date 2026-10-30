//
//  OnboardingShot.swift
//  BreezeSpeak
//
//  仅 DEBUG：把引导的四步离屏渲染成 PNG，落到 Documents/Shots，
//  再用 devicectl 从沙盒里取回来看版式。发布构建不含这段代码。
//
//  用法：devicectl device process launch <udid> com.breezespeak.app -onboarding-shot
//

#if DEBUG
import SwiftUI

enum OnboardingShot {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("-onboarding-shot")
    }

    @MainActor
    static func capture(env: AppEnvironment) {
        guard requested else { return }

        // 错落入场是 onAppear 驱动的，离屏渲染不会触发，先切成终态
        StaggerIn.instant = true

        // iPad Air 11" / Pro 11" 的逻辑尺寸（2x）
        let size = CGSize(width: 1180, height: 820)
        let dir = AppPaths.documents.appendingPathComponent("Shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for step in 0..<4 {
            let view = OnboardingFlow(startStep: step, snapshotMode: true, onFinish: {})
                .environmentObject(env)
                .environmentObject(env.model)
                .frame(width: size.width, height: size.height)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.uiImage, let data = image.pngData() else { continue }
            try? data.write(to: dir.appendingPathComponent("onboarding-\(step).png"))
        }
    }
}
#endif
