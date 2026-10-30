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

    /// 玻璃是自绘的，任何系统版本都有；留这个属性只为兼容旧调用点。
    static var isAvailableOnThisOS: Bool { true }
}

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = .regular
    if interactive { glass = glass.interactive() }
    if let tint { glass = glass.tint(tint) }
    return glass
}

/// 开关关掉时的替代底：实心毛玻璃 + 一条细线，安静、不抢戏。
private struct FlatSurface<S: InsettableShape>: View {
    var shape: S

    var body: some View {
        shape
            .fill(.regularMaterial)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.8))
    }
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
            content.background { FlatSurface(shape: shape) }
        }
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    @ObservedObject private var settings = GlassSettings.shared
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), settings.enabled {
            content.glassEffect(makeGlass(tint: tint, interactive: interactive), in: Capsule(style: .continuous))
        } else {
            content.background { FlatSurface(shape: Capsule(style: .continuous)) }
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

/// 玻璃容器：把相邻的玻璃归到同一个容器里，系统才会让它们在靠近时互相吸附、
/// 合流成一块（这是液态玻璃「会流动」的关键，单独一块块画是做不出来的）。
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

/// 主按钮：系统液态玻璃。
///
/// iOS 26 起直接交给 `glassEffect(.regular.tint(...).interactive())`：
/// 染色玻璃、按下时玻璃本身会有高光形变，都是系统渲染的，不自己画。
/// 禁用态不再是「25% 墨色 + 近白字」（白底上几乎看不见），
/// 改成浅染色玻璃 + 42% 字，读得出来但明显点不了。
struct PrimaryPillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ObservedObject private var glass = GlassSettings.shared

    var fillWidth: Bool = false
    var verticalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let label = configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Theme.inverse : Color.primary.opacity(0.42))
            .padding(.horizontal, 18)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .contentShape(shape)

        Group {
            if #available(iOS 26.0, *), glass.enabled {
                label.glassEffect(
                    .regular
                        .tint(Color.primary.opacity(isEnabled ? 0.88 : 0.16))
                        .interactive(isEnabled),
                    in: shape
                )
            } else {
                label.background {
                    shape.fill(Color.primary.opacity(isEnabled ? 1 : 0.10))
                }
            }
        }
        .scaleEffect(configuration.isPressed ? 0.965 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
        .onChangeCompat(of: configuration.isPressed) { _, pressed in
            if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }
}

/// 次要按钮：薄玻璃胶囊，压下去轻微内缩。
struct QuietPillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ObservedObject private var glass = GlassSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let label = configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.9 : 0.35))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(shape)

        Group {
            if #available(iOS 26.0, *), glass.enabled {
                label.glassEffect(.regular.interactive(isEnabled), in: shape)
            } else {
                label.background { FlatSurface(shape: shape) }
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(configuration.isPressed ? 0.92 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

extension View {
    func primaryPill() -> some View { buttonStyle(PrimaryPillStyle()) }
    func primaryPill(fillWidth: Bool, verticalPadding: CGFloat = 13) -> some View {
        buttonStyle(PrimaryPillStyle(fillWidth: fillWidth, verticalPadding: verticalPadding))
    }
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

// MARK: - Motion

/// 入场错落：每一步的第一屏内容按序号依次浮上来，避免整块同时出现。
///
/// 只改 opacity 与 offset，不参与布局，所以不会撑高页面或让 ScrollView 抖。
struct StaggerIn: ViewModifier {
    /// 离屏渲染（ImageRenderer）不会走 onAppear 里的动画，截图时直接关掉，
    /// 否则拍出来是一片空白。
    static var instant = false

    var index: Int
    var distance: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var revealed: Bool { shown || Self.instant || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : distance)
            .onAppear {
                guard !Self.instant, !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.46, dampingFraction: 0.86)
                    .delay(Double(index) * 0.055)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// 按序号错落入场（0 最先，往后每格多等 55ms）。
    func staggerIn(_ index: Int, distance: CGFloat = 10) -> some View {
        modifier(StaggerIn(index: index, distance: distance))
    }
}

/// iOS 17 才有 symbolEffect，低版本静默跳过。
extension View {
    @ViewBuilder
    func bounceSymbol(_ trigger: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
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
///
/// 出现时整块轻微上浮 + 放大淡入，标题栏比内容早一帧到位；
/// 关闭时先反向缩一下再真正 dismiss，避免「啪」地直接消失。
struct SheetChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    @State private var appeared = false

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
                Button { close() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .glassIconButton(size: 26)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -6)

            Divider().opacity(0.4)

            ScrollView {
                content()
                    .padding(20)
                    .padding(.bottom, 8)
            }
            .opacity(appeared ? 1 : 0)
        }
        .background(Theme.canvas)
        .scaleEffect(appeared ? 1 : 0.972, anchor: .center)
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeIn(duration: 0.15)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { dismiss() }
    }
}
