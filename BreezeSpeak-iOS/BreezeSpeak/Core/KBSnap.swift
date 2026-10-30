//
//  KBSnap.swift
//  BreezeSpeak
//
//  仅 DEBUG：键盘布局走查。
//  真机上没法从命令行截图，这里让 App 自己把窗口画出来存到 Documents：
//    1. 等界面就绪 → 找到正文输入框并让它成为第一响应者（弹出软件键盘）
//    2. 等键盘动画结束 → 把窗口渲染成 PNG，同时记录安全区与输入框位置
//  取图：xcrun devicectl device copy from --domain-type appDataContainer \
//        --domain-identifier com.breezespeak.app --source Documents/Shots
//

#if DEBUG
import SwiftUI
import UIKit

enum KBSnap {
    /// 布局探针：主界面把当前可用尺寸和安全区写进来，抓图时一并记录
    static var layoutNote = "(未记录)"

    static var requested: Bool {
        DebugHarness.action == "kb-shot" || DebugHarness.action == "plain-shot"
    }

    static func run() {
        // plain-shot：不聚焦，直接抓一张「键盘不在」的对照图
        if DebugHarness.action == "plain-shot" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { capture(name: "plain-window") }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            focusEditor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                capture(name: "kb-window")
            }
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private static func focusEditor() {
        guard let window = keyWindow() else { return }
        if let tv = firstTextView(in: window) {
            tv.becomeFirstResponder()
        }
    }

    private static func firstTextView(in view: UIView) -> UITextView? {
        if let tv = view as? UITextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

    private static func capture(name: String) {
        guard let window = keyWindow() else { return }
        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("\(name).png"))

        let insets = window.safeAreaInsets
        let scene = window.windowScene
        var report = """
        window bounds: \(bounds)
        safeAreaInsets: top \(insets.top) left \(insets.left) bottom \(insets.bottom) right \(insets.right)
        keyboard visible: \(insets.bottom > 0)
        """
        if let scene {
            report += "\ninterfaceOrientation: \(scene.interfaceOrientation.rawValue)"
        }
        if let tv = firstTextView(in: window) {
            let frame = tv.convert(tv.bounds, to: window)
            report += "\ntextView frame in window: \(frame)"
        }
        report += "\nlayout: \(layoutNote)"
        try? report.write(to: dir.appendingPathComponent("\(name)-report.txt"),
                          atomically: true, encoding: .utf8)
    }
}
#endif
