//
//  BreezeWidgetsBundle.swift
//  BreezeSpeak 小组件扩展
//
//  一个扩展里放三套：
//  · 桌面（小 / 中 / 大）
//  · 锁屏（圆形 / 矩形 / 行内）
//  · 控制中心（iOS 18 起，四个按钮）
//
//  控制中心那一组用 `if #available` 包着：系统 18 以下会直接跳过，
//  不会因为低版本设备缺 API 而装不上。
//

import SwiftUI
import WidgetKit

@main
struct BreezeWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        BreezeHomeWidget()
        BreezeLockWidget()

        if #available(iOS 18.0, *) {
            BreezeComposeControl()
            BreezeCloneControl()
            BreezeVoiceLibraryControl()
            BreezeDesignControl()
        }
    }
}
