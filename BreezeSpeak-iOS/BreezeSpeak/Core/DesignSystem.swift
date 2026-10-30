//
//  DesignSystem.swift
//  BreezeSpeak
//
//  与 macOS 版共用的一套控件：液态玻璃卡片/胶囊、主次按钮、分组标题、
//  小药丸、键值行、电平表。iOS 26+ 走系统 glassEffect，低版本退回材质。
//

import SwiftUI
import UIKit

// MARK: - Liquid Glass surfaces

/// 液态玻璃的开关状态。
///
/// 做成全局单例而不是走 EnvironmentObject：`glassCard()` / `glassCapsule()`
/// 是散落在几十处的修饰器，走环境值的话每处都得自己声明依赖、还得担心
/// sheet 里环境有没有继承对；单例 + @ObservedObject 能让关掉开关的瞬间
/// 所有玻璃面一起退回毛玻璃，不用逐层传值。
final class GlassSettings: ObservableObject {
    static let shared = GlassSettings()
    static let key = "breezespeak.liquidGlass"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    private init() {
        // 没存过 = 默认开启
        enabled = (UserDefaults.standard.object(forKey: Self.key) as? Bool) ?? true
    }

    /// 这套系统本身有没有液态玻璃（iOS 26 起才有）
    static var isAvailableOnThisOS: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = .regular
    if interactive { glass = glass.interactive() }
    if let tint { glass = glass.tint(tint) }
    return glass
}

private struct GlassCardModifier: ViewModifier {
    @ObservedObject private var settings = GlassSettings.shared
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *), settings.enabled {
            content.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.10), radius: 26, y: 12)
        }
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    @ObservedObject private var settings = GlassSettings.shared
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), settings.enabled {
            content.glassEffect(makeGlass(tint: tint, interactive: interactive), in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
    }
}

extension View {
    /// 圆角玻璃卡片。
    func glassCard(cornerRadius: CGFloat = Theme.radius,
                   tint: Color? = nil,
                   interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// 悬浮工具栏与 chips 用的胶囊玻璃。
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(GlassCapsuleModifier(tint: tint, interactive: interactive))
    }
}

/// 把多个玻璃形状归组，让它们之间可以互相形变（iOS 26+）。
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    @ObservedObject private var settings = GlassSettings.shared

    var body: some View {
        if #available(iOS 26.0, *), settings.enabled {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Buttons

struct PrimaryPillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inverse)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary)
                    .opacity(isEnabled ? 1 : 0.28)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct QuietPillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.9 : 0.35))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Theme.faintFill))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func primaryPill() -> some View { buttonStyle(PrimaryPillStyle()) }
    func quietPill() -> some View { buttonStyle(QuietPillStyle()) }

    /// 工具栏里的紧凑玻璃图标按钮。
    func glassIconButton(size: CGFloat = 30) -> some View {
        self
            .font(.system(size: 12.5, weight: .medium))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassCapsule()
            .foregroundStyle(.primary)
    }
}

// MARK: - 单色开关

/// 自绘开关。
///
/// 系统开关配 `.tint(.primary)` 在浅色下是「黑轨道 + 白滑块」，看着没问题；
/// 可 `.primary` 在深色下是白色，于是轨道和滑块一起变白，整块糊成一个白胶囊，
/// 既看不出开/关，夜里也很刺眼。这里把两态都做成反色：
///   开 → 轨道取主色（浅色黑 / 深色白），滑块取画布色（浅色近白 / 深色近黑）
///   关 → 轨道 10% 主色，滑块 42% 主色
/// 两种外观下都有明确对比，同时保持整套单色语言。
struct InkSwitchToggleStyle: ToggleStyle {
    var trackWidth: CGFloat = 44
    var trackHeight: CGFloat = 26
    var knobSize: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                track(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: configuration.isOn)
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "已开启" : "已关闭")
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func track(isOn: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isOn ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.10)))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(isOn ? 0 : 0.10), lineWidth: 0.8)
            )
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Theme.knob(isOn: isOn))
                    .frame(width: knobSize, height: knobSize)
                    .padding(.horizontal, 3)
                    .shadow(color: .black.opacity(isOn ? 0.18 : 0.06), radius: 1.5, y: 0.5)
            }
            .frame(width: trackWidth, height: trackHeight)
            .fixedSize()
    }
}

// MARK: - Small building blocks

struct SectionLabel: View {
    let text: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

struct Pill: View {
    var icon: String? = nil
    let text: String
    var emphasis: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
            }
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(emphasis ? Theme.inverse : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule(style: .continuous)
                .fill(emphasis ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Theme.faintFill))
        )
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// 极简电平表：随音量点亮条数。
struct LevelMeter: View {
    var level: Float
    var bars: Int = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                let threshold = Float(index) / Float(bars)
                Capsule()
                    .fill(threshold < level ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.16)))
                    .frame(width: 2.5, height: CGFloat(5.0 + Double(index % 6) * 2.5))
            }
        }
        .animation(.easeOut(duration: 0.18), value: level)
    }
}

/// 弹窗统一外壳：标题 + 关闭键 + 细分隔线 + 可滚动内容。
struct SheetChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .glassIconButton(size: 26)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().opacity(0.4)

            ScrollView {
                content()
                    .padding(20)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.canvas)
    }
}
