//
//  VoiceStore.swift
//  BreezeSpeak
//
//  我的声线库：内置 + 克隆 + 造声。克隆/造声声纹缓存到沙盒，最多 12 条克隆。
//

import Foundation
import SwiftUI
import UIKit

struct VoiceStoreSnapshot: Codable {
    var customVoices: [VoiceProfile] = []
    /// 内置音色的显示别名（只改名字，不改变原生 spk）
    var builtinAliases: [String: String] = [:]
    /// 内置声线被「编辑」后的完整快照（提示词 / 语速 / 指导强度）。
    /// 可选类型：老版本存档里没有这个键，用可选才能平滑解码。
    var builtinOverrides: [String: VoiceProfile]?
    var selectedVoiceID: UUID?
    var defaultVoiceID: UUID?
}

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

@MainActor
final class VoiceStore: ObservableObject {
    @Published private(set) var customVoices: [VoiceProfile] = []
    @Published private(set) var builtinAliases: [String: String] = [:]
    @Published private(set) var builtinOverrides: [String: VoiceProfile] = [:]
    @Published private(set) var selectedVoiceID: UUID
    @Published private(set) var defaultVoiceID: UUID

    init() {
        let snapshot = DiskStore.load(VoiceStoreSnapshot.self, from: AppPaths.voicesFile)
        let customs = snapshot?.customVoices ?? []
        customVoices = customs
        builtinAliases = snapshot?.builtinAliases ?? [:]
        builtinOverrides = snapshot?.builtinOverrides ?? [:]

        let fallback = VoiceProfile.builtins[0].id
        let def = snapshot?.defaultVoiceID.flatMap { id in
            (VoiceProfile.builtins + customs).first(where: { $0.id == id })?.id
        } ?? fallback
        defaultVoiceID = def

        let sel = snapshot?.selectedVoiceID.flatMap { id in
            (VoiceProfile.builtins + customs).first(where: { $0.id == id })?.id
        } ?? def
        selectedVoiceID = sel
    }

    // MARK: - 读取

    var builtinVoices: [VoiceProfile] {
        VoiceProfile.builtins.map { voice in
            var copy = builtinOverrides[voice.id.uuidString] ?? voice
            if let alias = builtinAliases[voice.id.uuidString] { copy.name = alias }
            return copy
        }
    }

    var cloneVoices: [VoiceProfile] { customVoices.filter { $0.kind == .clone } }
    var designVoices: [VoiceProfile] { customVoices.filter { $0.kind == .design } }
    var allVoices: [VoiceProfile] { builtinVoices + customVoices }

    var selectedVoice: VoiceProfile {
        allVoices.first(where: { $0.id == selectedVoiceID }) ?? builtinVoices[0]
    }

    var defaultVoice: VoiceProfile {
        allVoices.first(where: { $0.id == defaultVoiceID }) ?? builtinVoices[0]
    }

    func voice(id: UUID?) -> VoiceProfile? {
        guard let id else { return nil }
        return allVoices.first(where: { $0.id == id })
    }

    func voice(spk: String) -> VoiceProfile? {
        builtinVoices.first(where: { $0.spk == spk })
    }

    var cloneSlotsLeft: Int { max(0, AppConfig.maxCloneVoices - cloneVoices.count) }

    func isDefault(_ id: UUID) -> Bool { defaultVoiceID == id }

    func isBuiltin(_ id: UUID) -> Bool { VoiceProfile.builtins.contains(where: { $0.id == id }) }

    // MARK: - 写入

    func select(_ id: UUID) {
        guard allVoices.contains(where: { $0.id == id }) else { return }
        selectedVoiceID = id
        persist()
    }

    func setDefault(_ id: UUID) {
        guard allVoices.contains(where: { $0.id == id }) else { return }
        defaultVoiceID = id
        persist()
        Haptics.light()
    }

    @discardableResult
    func add(_ voice: VoiceProfile) -> VoiceProfile? {
        if voice.kind == .clone && cloneVoices.count >= AppConfig.maxCloneVoices {
            return nil
        }
        customVoices.append(voice)
        selectedVoiceID = voice.id
        persist()
        return voice
    }

    func rename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if VoiceProfile.builtins.contains(where: { $0.id == id }) {
            builtinAliases[id.uuidString] = trimmed
            persist()
            return
        }
        if let index = customVoices.firstIndex(where: { $0.id == id }) {
            customVoices[index].name = trimmed
            persist()
        }
    }

    func updateDefaultDirection(_ id: UUID, direction: String) {
        if let index = customVoices.firstIndex(where: { $0.id == id }) {
            customVoices[index].defaultDirection = direction
            persist()
        }
    }

    /// 编辑一条声线（名称、提示词、语速、指导强度…）。
    /// 内置声线不能改静态常量，所以把整份快照覆盖到 builtinOverrides 里。
    func update(_ voice: VoiceProfile) {
        if VoiceProfile.builtins.contains(where: { $0.id == voice.id }) {
            var stored = voice
            stored.kind = .builtin
            builtinOverrides[voice.id.uuidString] = stored
        } else if let index = customVoices.firstIndex(where: { $0.id == voice.id }) {
            customVoices[index] = voice
        } else {
            return
        }
        persist()
        Haptics.light()
    }

    func delete(_ id: UUID) {
        guard let victim = customVoices.first(where: { $0.id == id }) else { return }
        customVoices.removeAll { $0.id == id }

        if let name = victim.embeddingFileName {
            DiskStore.remove(AppPaths.embeddingsDirectory.appendingPathComponent(name))
        }
        if let name = victim.referenceFileName {
            DiskStore.remove(AppPaths.referencesDirectory.appendingPathComponent(name))
        }
        // 声线没了，音色锚点也不该留着占地方
        VoiceAnchor.invalidate(id)

        if selectedVoiceID == id { selectedVoiceID = defaultVoice.id }
        if defaultVoiceID == id { defaultVoiceID = VoiceProfile.builtins[0].id }
        persist()
    }

    // MARK: - 持久化

    private func persist() {
        let snapshot = VoiceStoreSnapshot(
            customVoices: customVoices,
            builtinAliases: builtinAliases,
            builtinOverrides: builtinOverrides,
            selectedVoiceID: selectedVoiceID,
            defaultVoiceID: defaultVoiceID
        )
        DiskStore.save(snapshot, to: AppPaths.voicesFile)
    }
}
