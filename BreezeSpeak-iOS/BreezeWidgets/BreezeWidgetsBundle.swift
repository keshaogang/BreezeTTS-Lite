//
//  BreezeWidgetsBundle.swift
//  BreezeSpeak 小组件扩展
//
//  一个扩展里放两套：桌面（小 / 中 / 大）与锁屏（圆形 / 矩形 / 行内）。
//

import SwiftUI
import WidgetKit

@main
struct BreezeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BreezeHomeWidget()
        BreezeLockWidget()
    }
}
