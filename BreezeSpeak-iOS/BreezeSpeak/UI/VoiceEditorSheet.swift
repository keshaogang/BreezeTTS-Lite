//
//  VoiceEditorSheet.swift
//  BreezeSpeak
//
//  单条声线的编辑器：名称 / 提示词 / 语速 / 指导强度。
//
//  三种声线可改的东西不一样：
//    · 内置 —— 提示词是那段英文声音描述，改它才是真的换音色；
//    · 造声 —— 提示词就是当初写的中文描述；
//    · 克隆 —— 音色由参考音频决定，提示词只是「文字微调」，
//              用来补语气、语速、气息，改不动这个人的音高。
//  改完之后这条声线的音色锚点会自动失效，下次生成会按新描述重新钉一遍。
//

import SwiftUI

struct VoiceEditorSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vm: SynthesisViewModel
    @Environment(\.dismiss) private var dismiss

    private let original: VoiceProfile

    @State private var name: String
    @State private var prompt: String
    @State private var referenceText: String
    @State private var speed: Double
    @State private var guidance: Double

    init(voice: VoiceProfile) {
        original = voice
        _name = State(initialValue: voice.displayName)
        _prompt = State(initialValue: Self.editablePrompt(for: voice))
        _referenceText = State(initialValue: voice.referenceText ?? "")
        _speed = State(initialValue: voice.speed)
        _guidance = State(initialValue: voice.guidanceScale)
    }

    private static func editablePrompt(for voice: VoiceProfile) -> String {
        switch voice.kind {
        case .builtin: return voice.nativeInstruction ?? voice.descriptor
        case .design: return voice.descriptor
        case .clone: return voice.tweak ?? ""
        }
    }

    private var promptTitle: String {
        switch original.kind {
        case .builtin: return "提示词（英文声音描述）"
        case .design: return "提示词"
        case .clone: return "文字微调（可选）"
        }
    }

    private var promptHint: String {
        switch original.kind {
        case .builtin:
            return "引擎按这段描述决定音高、音色、口音。改一个字都可能换一个人，建议整句替换而不是随手改。"
        case .design:
            return "年龄、性别、音色、沙哑或清亮、气息、口音风格。写得越具体越稳定。"
        case .clone:
            return "音色由参考音频决定，这里只加语气与节奏。例：语速稍慢，语气更温柔，尾音收住。留空就完全按参考音频来。"
        }
    }

    var body: some View {
        SheetChrome(title: "编辑「\(original.displayName)」",
                    subtitle: "改的是这条声线的固定属性，保存后立刻生效") {
            VStack(alignment: .leading, spacing: 18) {
                nameField
                promptField
                if original.kind == .clone { referenceTextField }
                sliders
                actions
            }
        }
        .sheetCanvasBackground(Theme.canvas)
    }

    /// 编辑器里的字段标题：比 SectionLabel 更实一点，方便一眼找到要改哪一块
    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: - 名称

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("名称")
            TextField("给它起个名字", text: $name)
                .font(.system(size: 16, weight: .semibold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.faintFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
    }

    // MARK: - 提示词

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                fieldLabel(promptTitle)
                Spacer(minLength: 0)
                Text("\(prompt.count) 字")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .frame(height: original.kind == .clone ? 72 : 104)
                    .padding(6)

                if prompt.isEmpty {
                    Text(original.kind == .clone
                         ? "例：语速稍慢，语气更温柔，尾音收住。"
                         : "例：三十岁女性，中低音，略带沙哑，气息偏弱，深夜电台感。")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.faintFill))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            Text(promptHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 参考原文（仅克隆）

    private var referenceTextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("参考音频原话")
            TextEditor(text: $referenceText)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(height: 54)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.faintFill))
            Text("必须和参考音频里说的字逐字对得上，否则克隆会串音。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 参数

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("参数")
            sliderRow("语速", value: $speed, range: 0.7...1.3, hint: "这条声线默认的语速倍率")
            sliderRow("指导强度 cfg_scale", value: $guidance, range: AppConfig.guidanceRange,
                      hint: "1.0 自然 · 2~3 让标记生效 · 超过 3 开始发刺")
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.05).tint(Theme.controlTint)
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 操作

    private var actions: some View {
        HStack(spacing: 8) {
            Button("保存") { save() }
                .primaryPill()
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if original.kind != .clone {
                Button("重新固定音色") {
                    VoiceAnchor.invalidate(original.id)
                    AudioCache.clear()
                    vm.showToast("已清掉锚点，下次生成会按新描述重新固定")
                }
                .quietPill()
            }

            Spacer(minLength: 0)

            Button("取消") { dismiss() }
                .quietPill()
        }
    }

    private func save() {
        var updated = original
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { updated.name = trimmedName }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        switch original.kind {
        case .builtin:
            updated.nativeInstruction = trimmedPrompt.isEmpty ? nil : trimmedPrompt
        case .design:
            updated.descriptor = trimmedPrompt
        case .clone:
            updated.tweak = trimmedPrompt.isEmpty ? nil : trimmedPrompt
            updated.referenceText = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        updated.speed = speed
        updated.guidanceScale = guidance

        // 只有「音色身份」真变了（提示词 / 语速 / 强度）才清锚点与音频缓存；
        // 单纯改个名字不该把已经攒下来的缓存全废掉。
        if VoiceAnchor.fingerprint(for: updated) != VoiceAnchor.fingerprint(for: original) {
            VoiceAnchor.invalidate(updated.id)
            AudioCache.clear()
        }

        env.voices.update(updated)
        if env.voices.selectedVoiceID == updated.id {
            vm.guidanceScale = updated.guidanceScale
        }
        vm.showToast("已保存「\(updated.displayName)」")
        dismiss()
    }
}
