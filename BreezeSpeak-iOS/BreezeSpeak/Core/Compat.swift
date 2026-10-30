//
//  Compat.swift
//  BreezeSpeak
//
//  向下兼容层：把 iOS 17 / 18 才有的修饰器包成可用的形式，让同一份代码
//  在 iPadOS 16 上也能编、也能跑。这里只做 API 形态适配，不改视觉。
//

import SwiftUI

// MARK: - onChange

extension View {
    /// `onChange(of:) { old, new in }` 是 iOS 17 才有的签名。
    /// 包一层之后，iOS 16 上会用自持的 previous 还原出真正的旧值，
    /// 所以下面那些「比较新旧文本」的判断在低版本上依然成立。
    func onChangeCompat<V: Equatable>(
        of value: V,
        perform action: @escaping (_ old: V, _ new: V) -> Void
    ) -> some View {
        modifier(CompatOnChange(value: value, action: action))
    }

    /// `presentationSizing(.page)` 需要 iOS 18；低版本交给系统默认的 sheet 尺寸。
    @ViewBuilder
    func pageSheetSizing() -> some View {
        if #available(iOS 18.0, *) {
            self.presentationSizing(.page)
        } else {
            self
        }
    }

    /// `presentationBackground` 需要 iOS 16.4。16.0–16.3 上不设，
    /// 内容自身（SheetChrome）已经铺了画布色，观感一致。
    @ViewBuilder
    func sheetCanvasBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(color)
        } else {
            self
        }
    }
}

private struct CompatOnChange<V: Equatable>: ViewModifier {
    let value: V
    let action: (V, V) -> Void

    @State private var previous: V?
    @State private var primed = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 17.0, *) {
                content.onChange(of: value) { old, new in
                    action(old, new)
                }
            } else {
                content.onChange(of: value) { new in
                    let old = primed ? (previous ?? new) : new
                    previous = new
                    primed = true
                    action(old, new)
                }
            }
        }
        .onAppear {
            // 首次出现只记录基准值，不触发动作
            if !primed {
                previous = value
                primed = true
            }
        }
    }
}

// MARK: - 版本文案

enum SystemInfo {
    /// 「iPadOS 18+」这类文案随真实系统走，不写死
    static var osVersionText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iPadOS \(v.majorVersion)+"
    }
}
