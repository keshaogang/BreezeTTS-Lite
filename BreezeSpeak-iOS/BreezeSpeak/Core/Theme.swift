//
//  Theme.swift
//  BreezeSpeak
//
//  与 macOS 版完全一致的单色设计语言：系统背景 + 语义前景 + 极细分隔线。
//  不硬编码任何颜色，浅色/深色随系统自动翻转。
//

import SwiftUI
import UIKit

enum Theme {
    static let radius: CGFloat = 26
    static let controlRadius: CGFloat = 15

    /// 对齐 macOS 的 windowBackgroundColor：浅色 #F2F2F7、深色 #1C1C1E
    static var canvas: Color { Color(uiColor: .secondarySystemBackground) }
    static var hairline: Color { Color.primary.opacity(0.09) }
    static var faintFill: Color { Color.primary.opacity(0.05) }
    static var softFill: Color { Color.primary.opacity(0.08) }
    /// 窗口背景的反色：主按钮与选中态用它，「黑底白字」在深色下自动反转。
    static var inverse: Color { Color(uiColor: .secondarySystemBackground) }

    /// 滑块等系统控件的着色。
    /// 不能直接用 .primary：深色下它是白色，白色填充轨道 + 白色滑块 = 滑块被吃掉。
    /// 深色改中灰，滑块（系统固定白色）与轨道之间才有对比。
    static var controlTint: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.systemGray : UIColor.label
        })
    }

    /// 开关轨道上的滑块色。开着时取画布色（浅色下近白、深色下近黑），
    /// 与 primary 轨道互为反色；关着时取中灰，避免和轨道糊在一起。
    static func knob(isOn: Bool) -> Color {
        isOn ? canvas : Color.primary.opacity(0.42)
    }
}

/// 兼容层：少量仍在使用的语义色名，全部收敛到单色体系，
/// 避免播放器、内存监视等旧文件大面积改动。
enum Palette {
    static var ink: Color { .primary }
    static var inkSecondary: Color { .secondary }
    static var inkTertiary: Color { Color(uiColor: .tertiaryLabel) }
    static var surface: Color { Theme.faintFill }
    static var stroke: Color { Theme.hairline }
    static var selectionFill: Color { Theme.softFill }
    static var accent: Color { .primary }
    static var danger: Color { Color(uiColor: .systemRed) }
    static var mint: Color { .secondary }
    static var peach: Color { .secondary }
    static var lilac: Color { .secondary }
}

enum Typo {
    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: .semibold) }
    static func section(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size) }
    static func mono(_ size: CGFloat = 11) -> Font { .system(size: size, design: .monospaced) }
    static func caption(_ size: CGFloat = 10.5) -> Font { .system(size: size) }
}
