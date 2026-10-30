//
//  BreezeControls.swift
//  BreezeSpeak 小组件扩展
//
//  控制中心（iOS 18 起）里的快捷按钮。每个按钮就是一个 AppIntent，
//  点下去系统把 App 拉起来，再在 App 进程里把「要跳到哪」交出去。
//
//  为什么不用 Toggle：控制中心的开关必须有一个能读能写的布尔状态，
//  而 App 的数据在沙盒里、扩展拿不到（没有 App Group 授权），
//  硬做一个开关只会显示成「永远关着」。按钮是真能用的形态。
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 新建朗读

@available(iOS 18.0, *)
struct BreezeComposeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BreezeComposeControl") {
            ControlWidgetButton(action: OpenBreezeIntent(route: .compose)) {
                Label("新建朗读", systemImage: "waveform")
            }
        }
        .displayName("新建朗读")
        .description("打开 BreezeSpeak，写一段新文本开始朗读。")
    }
}

// MARK: - 快速克隆

@available(iOS 18.0, *)
struct BreezeCloneControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BreezeCloneControl") {
            ControlWidgetButton(action: OpenBreezeIntent(route: .clone)) {
                Label("克隆声音", systemImage: "waveform.badge.mic")
            }
        }
        .displayName("克隆声音")
        .description("直接进到声音克隆：录 5~30 秒，本机提取声纹。")
    }
}

// MARK: - 音色库

@available(iOS 18.0, *)
struct BreezeVoiceLibraryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BreezeVoiceLibraryControl") {
            ControlWidgetButton(action: OpenBreezeIntent(route: .voices)) {
                Label("音色库", systemImage: "person.wave.2")
            }
        }
        .displayName("音色库")
        .description("换声线、改语速与指导强度。")
    }
}

// MARK: - 文字造声

@available(iOS 18.0, *)
struct BreezeDesignControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BreezeDesignControl") {
            ControlWidgetButton(action: OpenBreezeIntent(route: .design)) {
                Label("文字造声", systemImage: "sparkles")
            }
        }
        .displayName("文字造声")
        .description("用一段描述捏一条新声线。")
    }
}
