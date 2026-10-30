//
//  WidgetShot.swift
//  BreezeSpeak
//
//  仅 DEBUG：把每一种小组件尺寸离屏渲染成 PNG，写进 Documents/Shots。
//
//  小组件扩展本身没法在 App 进程里跑，但它的版式代码在 SharedWidgetUI/ 里，
//  App 也编译同一份，所以这里可以按真实尺寸原样画一遍，用来检查
//  「文字有没有溢出、元素有没有挤在一起」，不必真的把小组件加到桌面上。
//

#if DEBUG
import SwiftUI

enum WidgetShot {
    static var requested: Bool { DebugHarness.action == "widget-shot" }

    /// 尺寸取 iPad 桌面小组件的内容区（系统已扣掉四周 16pt 边距），
    /// 锁屏按 72×72 与 160×72 的常用绘制区。
    private static let cases: [(name: String, size: CGSize, build: @MainActor () -> AnyView)] = [
        ("widget-small", CGSize(width: 158, height: 158), { AnyView(HomeSmallCard()) }),
        ("widget-medium", CGSize(width: 330, height: 158), { AnyView(HomeMediumCard()) }),
        ("widget-large", CGSize(width: 330, height: 354), { AnyView(HomeWideCard()) }),
        ("widget-lock-circle", CGSize(width: 72, height: 72), { AnyView(LockCircleCard()) }),
        ("widget-lock-rect", CGSize(width: 160, height: 72), { AnyView(LockRectCard()) })
    ]

    @MainActor
    static func capture() {
        guard requested else { return }

        let dir = AppPaths.documents
            .appendingPathComponent("BreezeSpeak/Shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "-dark" : ""
            for item in cases {
                let card = item.build()
                    .frame(width: item.size.width, height: item.size.height)
                    .padding(16)
                    .background(WidgetInk.paper)
                    .environment(\.colorScheme, scheme)

                let renderer = ImageRenderer(content: card)
                renderer.scale = 3
                guard let image = renderer.uiImage,
                      let data = image.pngData() else { continue }
                try? data.write(to: dir.appendingPathComponent("\(item.name)\(suffix).png"))
            }
        }

        // 留一份尺寸清单，方便对图时确认没有裁切
        var report = "widget snapshot @ \(Date())\n"
        for item in cases {
            report += "\(item.name): \(Int(item.size.width))x\(Int(item.size.height))\n"
        }
        try? report.write(to: dir.appendingPathComponent("widget-report.txt"),
                          atomically: true, encoding: .utf8)
    }
}
#endif
