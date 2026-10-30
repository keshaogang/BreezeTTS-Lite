//
//  HomeWidget.swift
//  BreezeSpeak 桌面小组件
//
//  内容是「启动器 + 速查」：小组件进程读不到 App 沙盒（没有 App Group 授权），
//  所以不做数据展示，只把最常用的三个动作和停顿标记摆在桌面上，点哪进哪。
//

import SwiftUI
import WidgetKit

// MARK: - 时间线

struct BreezeWidgetEntry: TimelineEntry {
    var date: Date
}

struct BreezeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BreezeWidgetEntry {
        BreezeWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BreezeWidgetEntry) -> Void) {
        completion(BreezeWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BreezeWidgetEntry>) -> Void) {
        // 内容与时间无关，给一条长期有效的时间线即可，避免无意义的刷新耗电
        completion(Timeline(entries: [BreezeWidgetEntry(date: Date())], policy: .never))
    }
}

// MARK: - 视图

struct BreezeHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                HomeSmallCard()
            case .systemLarge, .systemExtraLarge:
                HomeWideCard()
            default:
                HomeMediumCard()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCanvas(WidgetInk.paper)
        // 小尺寸只支持一个整体点击目标；中大尺寸里的 Link 会各自生效
        .widgetURL(WidgetLink.compose.url)
    }
}

// MARK: - Widget

struct BreezeHomeWidget: Widget {
    private let kind = "BreezeHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreezeWidgetProvider()) { _ in
            BreezeHomeWidgetView()
        }
        .configurationDisplayName("BreezeSpeak")
        .description("一键开始朗读，顺带记住停顿标记的写法。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
