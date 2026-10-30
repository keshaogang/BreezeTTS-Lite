//
//  WidgetCompat.swift
//  BreezeSpeak 小组件扩展
//
//  只在扩展里可用的 WidgetKit 修饰，单独放一份，避免污染 App 也编译的共享视图。
//

import SwiftUI
import WidgetKit

extension View {
    /// iOS 17 起小组件背景必须走 containerBackground，低版本只能自己铺一层。
    @ViewBuilder
    func widgetCanvas(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}
