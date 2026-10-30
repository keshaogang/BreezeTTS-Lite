//
//  KeyboardObserver.swift
//  BreezeSpeak
//
//  键盘形态监听。三种情况要区别对待：
//
//  · 贴底的全屏键盘 —— 底部工具栏必须跟着往上抬，否则正文和工具栏都被压在键盘下面；
//  · 悬浮 / 拆分键盘 —— 它本身是一块浮窗，页面不该为它让位，工具栏保持原位；
//  · 外接键盘 —— 根本没有软件键盘，连「收起键盘」都不该出现。
//
//  系统默认的键盘安全区对前两种一视同仁，所以这里自己读键盘 frame，
//  再配合 .ignoresSafeArea(.keyboard) 手动控制底部 inset。
//

import SwiftUI
import UIKit

@MainActor
final class KeyboardObserver: ObservableObject {
    /// 键盘实际高度（悬浮键盘也照实记录）
    @Published private(set) var rawHeight: CGFloat = 0
    /// 是否悬浮 / 拆分键盘：宽度明显小于屏幕宽度
    @Published private(set) var isFloating = false

    /// 软件键盘是否在屏幕上（外接键盘时为 false）
    var isVisible: Bool { rawHeight > 1 }

    /// 需要参与布局的键盘高度：悬浮键盘返回 0，工具栏保持原位。
    ///
    /// 键盘 frame 是从屏幕底边量的，而 safeAreaInset 的内容本来就坐在
    /// home indicator 安全区之上；直接加上整段键盘高度会多让出约 20~30pt，
    /// 工具栏和键盘之间留出一道空缝。所以这里先减掉底部安全区。
    var dockedHeight: CGFloat {
        guard isVisible, !isFloating else { return 0 }
        return max(0, rawHeight - bottomSafeInset)
    }

    private var bottomSafeInset: CGFloat = 0

    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillHideNotification
        ]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.apply(note) }
            })
        }
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
    }

    private func apply(_ note: Notification) {
        bottomSafeInset = keyWindow?.safeAreaInsets.bottom ?? 0

        guard note.name != UIResponder.keyboardWillHideNotification,
              let info = note.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            rawHeight = 0
            isFloating = false
            return
        }

        let screen = currentScreenBounds
        if frame.minY >= screen.maxY - 1 {
            rawHeight = 0
            isFloating = false
            return
        }

        rawHeight = max(0, screen.maxY - frame.minY)
        // 悬浮键盘在 iPad 上约 320pt 宽，拆分键盘更窄；全屏键盘贴着两边
        isFloating = frame.width < screen.width * 0.92
    }

    private var currentScreenBounds: CGRect {
        if let scene = activeScene {
            return scene.screen.bounds
        }
        return UIScreen.main.bounds
    }

    private var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    private var keyWindow: UIWindow? {
        activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
    }
}
