//
//  WidgetDesign.swift
//  BreezeSpeak 小组件视觉层
//
//  纯 SwiftUI，不依赖 WidgetKit，因此 App 与小组件扩展可以共用同一份。
//  好处是可以在 App 里用离屏渲染把每种尺寸画出来自查版式，不用真机截图。
//

import SwiftUI
import UIKit

// MARK: - 配色

/// 小组件自带的极简单色体系，与 App 内的 Theme 一致：
/// 只有「纸」和「墨」两端，靠透明度做层级，深浅色自动翻转。
enum WidgetInk {
    static var paper: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                : UIColor(red: 0.955, green: 0.955, blue: 0.965, alpha: 1)
        })
    }

    static var paperDeep: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        })
    }

    static var ink: Color { .primary }
    static var secondary: Color { Color.primary.opacity(0.55) }
    static var tertiary: Color { Color.primary.opacity(0.34) }
    static var hairline: Color { Color.primary.opacity(0.10) }
    static var fill: Color { Color.primary.opacity(0.06) }
}

// MARK: - 深链

/// 小组件点按后跳转的目标。App 侧在 onOpenURL 里解析。
enum WidgetLink: String {
    case compose
    case clone
    case design
    case voices
    case history
    case settings

    var url: URL {
        URL(string: "breezespeak://\(rawValue)")!
    }

    static func parse(_ url: URL) -> WidgetLink? {
        guard url.scheme == "breezespeak" else { return nil }
        let host = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        return WidgetLink(rawValue: host)
    }
}

// MARK: - 波形

/// 固定高度的竖条波形，纯装饰。锁屏上会被系统统一着色。
struct WidgetWaveform: View {
    var bars: [CGFloat] = [0.34, 0.62, 1.0, 0.74, 0.46, 0.88, 0.55, 0.3]
    var barWidth: CGFloat = 3
    var gap: CGFloat = 3
    var maxHeight: CGFloat = 22
    var opacity: Double = 0.9

    var body: some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, ratio in
                Capsule(style: .continuous)
                    .fill(WidgetInk.ink.opacity(opacity))
                    .frame(width: barWidth, height: max(2, maxHeight * ratio))
            }
        }
        .frame(height: maxHeight, alignment: .center)
    }
}

// MARK: - 入口胶囊

struct WidgetEntry: View {
    var icon: String
    var title: String
    var detail: String?
    var link: WidgetLink

    var body: some View {
        Link(destination: link.url) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(WidgetInk.ink.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(WidgetInk.ink)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(WidgetInk.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(WidgetInk.fill)
            )
        }
        // 小组件里的 Link 不带高亮反馈，这里保持静态即可
        .buttonStyle(.plain)
    }
}

// MARK: - 说明
//
//  这个文件被 App 与小组件扩展同时编译，所以只能依赖 SwiftUI 本身：
//  containerBackground / widgetAccentable 属于 WidgetKit，放在扩展侧的 Compat.swift。

