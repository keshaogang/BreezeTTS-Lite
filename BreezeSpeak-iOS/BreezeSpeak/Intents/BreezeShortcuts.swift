//
//  BreezeShortcuts.swift
//  BreezeSpeak
//
//  快捷指令 App 里能用的全部动作，以及免配置短语。
//
//  分两类：
//  · 导航类：openAppWhenRun = true，把 App 拉起来并跳到指定界面（克隆 / 造声 / 音色库…）
//  · 数据类：不打开 App，直接读写声线库（设默认声线 / 列出声线 / 查当前声线）
//  两类都在 App 进程里跑，所以拿到的就是用户真正那份数据，不存在两份存档。
//

import AppIntents
import Foundation

// MARK: - 快速克隆

struct QuickCloneIntent: AppIntent {
    static var title: LocalizedStringResource = "快速克隆声音"
    static var description = IntentDescription(
        "直接跳到声音克隆：对着 iPad 说 5~30 秒，本机提取声纹生成一条新声线。不联网、不上传录音。",
        categoryName: "声线"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        BreezeRouter.deliver(.clone)
        return .result(dialog: IntentDialog("打开声音克隆，说 5~30 秒就好"))
    }
}

// MARK: - 文字造声

struct DesignVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "文字造声"
    static var description = IntentDescription(
        "用一段文字描述（例：低沉的中年男声，语速慢，略带沙哑）捏一条新声线。",
        categoryName: "声线"
    )
    static var openAppWhenRun: Bool = true

    /// 顺手把描述带过去，进到页面就是填好的。
    @Parameter(title: "音色描述", description: "例如：清亮的女声，语速偏快，语气活泼")
    var descriptor: String?

    static var parameterSummary: some ParameterSummary {
        Summary("用描述造一条声线 \(\.$descriptor)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let descriptor {
            UserDefaults.standard.set(descriptor, forKey: "breezespeak.design.pendingDescriptor")
        }
        BreezeRouter.deliver(.design)
        return .result(dialog: IntentDialog("打开文字造声"))
    }
}

// MARK: - 设默认声线

struct SetDefaultVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "设置默认声线"
    static var description = IntentDescription(
        "把某条声线设为默认：之后每次生成、以及所有快捷指令里「留空声线」的地方都用它。",
        categoryName: "声线"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "声线")
    var voice: VoiceChoice

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$voice) 设为默认声线")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VoiceStore()
        guard let uuid = UUID(uuidString: voice.id), let profile = store.voice(id: uuid) else {
            throw TTSError.voiceNotFound
        }
        store.setDefault(profile.id)
        store.select(profile.id)
        return .result(dialog: IntentDialog("默认声线已换成 \(profile.displayName)"))
    }
}

// MARK: - 查声线

struct CurrentVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "获取当前默认声线"
    static var description = IntentDescription("返回默认声线的名字，可以接在其它动作后面做判断。",
                                               categoryName: "声线")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let voice = VoiceStore().defaultVoice
        return .result(value: voice.displayName, dialog: IntentDialog("当前默认声线：\(voice.displayName)"))
    }
}

struct ListVoicesIntent: AppIntent {
    static var title: LocalizedStringResource = "列出声线"
    static var description = IntentDescription("返回声线名字列表（内置 + 克隆 + 造声），可以用来遍历或做选择。",
                                               categoryName: "声线")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let all = VoiceStore().allVoices
        let names = all.map(\.displayName)
        return .result(value: names,
                       dialog: IntentDialog("共 \(all.count) 条声线：\(names.prefix(5).joined(separator: "、"))"))
    }
}

// MARK: - 免配置短语

/// 装好 App 就能在快捷指令 / Siri 里直接说，不用先手动建动作。
/// 上限 10 条，这里按「生成 → 克隆 → 造声 → 导航」排优先级。
struct BreezeSpeakShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateSpeechIntent(),
            phrases: [
                "用 \(.applicationName) 生成播报",
                "让 \(.applicationName) 朗读这段话",
                "用 \(.applicationName) 生成语音"
            ],
            shortTitle: "生成播报音频",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: QuickCloneIntent(),
            phrases: [
                "用 \(.applicationName) 克隆声音",
                "\(.applicationName) 快速克隆"
            ],
            shortTitle: "快速克隆声音",
            systemImageName: "waveform.badge.mic"
        )
        AppShortcut(
            intent: DesignVoiceIntent(),
            phrases: [
                "用 \(.applicationName) 造一个声音"
            ],
            shortTitle: "文字造声",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SetDefaultVoiceIntent(),
            phrases: [
                "用 \(.applicationName) 把 \(\.$voice) 设为默认"
            ],
            shortTitle: "设置默认声线",
            systemImageName: "person.wave.2"
        )
        AppShortcut(
            intent: OpenBreezeIntent(),
            phrases: [
                "打开 \(.applicationName) 的\(\.$route)"
            ],
            shortTitle: "打开界面",
            systemImageName: "arrow.up.forward.app"
        )
    }
}
