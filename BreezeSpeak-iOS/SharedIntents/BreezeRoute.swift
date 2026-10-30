//
//  BreezeRoute.swift
//  BreezeSpeak 共享路由
//
//  这个文件同时编进 App 与小组件扩展：
//  桌面小组件、锁屏小组件、控制中心按钮、快捷指令，全部用同一套落点定义，
//  避免「控件写一个字符串、App 里再猜一遍」这种对不上的情况。
//

import AppIntents
import Foundation

// MARK: - 落点

/// App 内部可以被外部直接叫到的六个地方。
enum BreezeRoute: String, AppEnum, CaseIterable, Sendable {
    case compose
    case clone
    case design
    case voices
    case history
    case settings

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "页面")

    static var caseDisplayRepresentations: [BreezeRoute: DisplayRepresentation] = [
        .compose: DisplayRepresentation(title: "新建朗读"),
        .clone: DisplayRepresentation(title: "声音克隆"),
        .design: DisplayRepresentation(title: "文字造声"),
        .voices: DisplayRepresentation(title: "音色库"),
        .history: DisplayRepresentation(title: "历史记录"),
        .settings: DisplayRepresentation(title: "设置")
    ]

    /// 深链：breezespeak://clone 这样。
    var url: URL {
        URL(string: "breezespeak://\(rawValue)")!
    }

    var title: String {
        switch self {
        case .compose: return "新建朗读"
        case .clone: return "声音克隆"
        case .design: return "文字造声"
        case .voices: return "音色库"
        case .history: return "历史记录"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .compose: return "waveform"
        case .clone: return "waveform.badge.mic"
        case .design: return "sparkles"
        case .voices: return "person.wave.2"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }

    static func parse(_ url: URL) -> BreezeRoute? {
        guard url.scheme == "breezespeak" else { return nil }
        let host = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        return BreezeRoute(rawValue: host)
    }
}

// MARK: - 投递

/// 把「要跳到哪」交给 App。
///
/// 控制中心按钮的 intent 带 `openAppWhenRun`，系统会把 App 拉起来、并在 **App 进程内**
/// 执行 perform，所以这里的 UserDefaults 就是 App 自己的那份；同时再发一条通知，
/// 让已经在运行的 App 立刻响应，不必等下一次回到前台。
enum BreezeRouter {
    static let pendingRouteKey = "breezespeak.route.pending"
    static let pendingStampKey = "breezespeak.route.stamp"
    static let requested = Notification.Name("breezespeak.route.requested")

    static func deliver(_ route: BreezeRoute) {
        let defaults = UserDefaults.standard
        defaults.set(route.rawValue, forKey: pendingRouteKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingStampKey)
        NotificationCenter.default.post(name: requested, object: nil,
                                        userInfo: ["route": route.rawValue])
    }

    /// 取走待处理的落点（取一次就清掉，避免切回前台又被弹一次）。
    static func takePending(maxAge: TimeInterval = 20) -> BreezeRoute? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: pendingRouteKey) else { return nil }
        let stamp = defaults.double(forKey: pendingStampKey)
        defaults.removeObject(forKey: pendingRouteKey)
        defaults.removeObject(forKey: pendingStampKey)
        guard Date().timeIntervalSince1970 - stamp <= maxAge else { return nil }
        return BreezeRoute(rawValue: raw)
    }
}

// MARK: - 通用「打开」意图

/// 控制中心按钮与快捷指令共用：跳到指定界面。
///
/// 用 AppIntent 而不是纯 URL 的原因：控制中心只认 intent，
/// 而 intent 又能在快捷指令里当动作反复串联，一份实现两处可用。
struct OpenBreezeIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 BreezeSpeak"
    static var description = IntentDescription(
        "直接跳到 BreezeSpeak 的指定界面：新建朗读、声音克隆、文字造声、音色库、历史或设置。",
        categoryName: "导航"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "界面")
    var route: BreezeRoute

    init() {
        route = .compose
    }

    init(route: BreezeRoute) {
        self.route = route
    }

    static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$route)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        BreezeRouter.deliver(route)
        return .result(dialog: IntentDialog("正在打开\(route.title)"))
    }
}
