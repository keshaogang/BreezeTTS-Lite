//
//  WindowChrome.swift
//  BreezeSpeak
//
//  宿主窗口底色。
//
//  SwiftUI 只负责画自己的内容区，内容区之外露出的是 UIWindow 的默认底色（白）。
//  这在这几种情况下会露出来：
//    · 软件键盘弹出，内容区被压缩，键盘上方留出窗口底色；
//    · iPad App 跑在 Apple Silicon Mac 上，窗口被拉伸；
//    · 旋转 / 分屏尺寸变化的中途。
//  统一把窗口底色刷成画布色，露出来的那块就跟页面同色，不再是一条白边。
//

import SwiftUI
import UIKit

/// 探针视图：挂在视图树上，只为拿到 `view.window` 把底色刷掉。
private struct WindowBackgroundSetter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        return probe
    }

    func updateUIView(_ probe: UIView, context: Context) {
        paint(from: probe, attempt: 0)
    }

    /// 视图刚挂上去时 `window` 还是 nil，等下一轮 runloop 再取一次；
    /// 再取不到就退化成「跟着 trait 变化重试」，键盘弹出时也正好会走到这里。
    private func paint(from probe: UIView, attempt: Int) {
        DispatchQueue.main.async {
            if let window = probe.window {
                window.backgroundColor = .secondarySystemBackground
            } else if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    paint(from: probe, attempt: attempt + 1)
                }
            }
        }
    }
}

extension View {
    /// 把宿主窗口底色刷成画布色（`secondarySystemBackground`，动态色，深浅色自动跟随）。
    func canvasWindowBackground() -> some View {
        background(
            WindowBackgroundSetter()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}
