//
//  LockWidget.swift
//  BreezeSpeak 锁屏小组件
//
//  锁屏只给两种信息：这是谁（品牌 + 波形）和按下去会怎样（开始朗读）。
//  刻意不塞文字预览：锁屏是公共场合，内容不该被旁人一眼看全。
//

import SwiftUI
import WidgetKit

struct BreezeLockWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            // 锁屏按系统着色规则渲染，开启后波形与文字会跟随整屏的强调色
            .widgetAccentable()
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            LockInlineCard()
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                LockCircleCard()
            }
        default:
            LockRectCard()
        }
    }
}

struct BreezeLockWidget: Widget {
    private let kind = "BreezeLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreezeWidgetProvider()) { _ in
            BreezeLockWidgetView()
                .widgetURL(WidgetLink.compose.url)
        }
        .configurationDisplayName("BreezeSpeak 朗读")
        .description("在锁屏上直接进入朗读。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
