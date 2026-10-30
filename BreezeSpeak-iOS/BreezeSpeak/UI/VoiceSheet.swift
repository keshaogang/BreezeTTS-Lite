//
//  VoiceSheet.swift
//  BreezeSpeak
//
//  我的声线库：内置 / 声音克隆 / 文字造声 三个 Tab，
//  外加 Voice Direction 演绎指令与全局语速。视觉语言与 macOS 版一致。
//

import SwiftUI
import UniformTypeIdentifiers

struct VoiceSheet: View {
    enum LabTab: String, CaseIterable, Identifiable {
        case builtin = "内置"
        case clone = "克隆"
        case design = "造声"
        var id: String { rawValue }
    }

    @StateObject private var lab: VoiceLabModel
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vm: SynthesisViewModel

    @State private var tab: LabTab = .builtin
    @State private var showImporter = false
    @State private var renameTarget: VoiceProfile?
    @State private var renameText = ""
    @State private var editingVoice: VoiceProfile?

    init(lab: VoiceLabModel) {
        _lab = StateObject(wrappedValue: lab)
    }

    var body: some View {
        SheetChrome(title: "音色",
                    subtitle: "选一条声线；每行右侧的「编辑」可以改名称、提示词与语速") {
            VStack(alignment: .leading, spacing: 20) {
                Picker("", selection: $tab) {
                    ForEach(LabTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                tuningSection

                Divider().opacity(0.4)

                switch tab {
                case .builtin: builtinTab
                case .clone: cloneTab
                case .design: designTab
                }
            }
        }
        .sheet(item: $editingVoice) { voice in
            VoiceEditorSheet(voice: voice)
                .environmentObject(env)
                .environmentObject(vm)
                .pageSheetSizing()
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio, .wav, .mpeg4Audio],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                lab.importAudio(url: url)
                tab = .clone
            }
        }
        .alert(item: $lab.alert) { payload in
            Alert(title: Text(payload.title), message: Text(payload.message),
                  dismissButton: .default(Text("知道了")))
        }
        .alert("重命名声线", isPresented: Binding(get: { renameTarget != nil },
                                              set: { if !$0 { renameTarget = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget {
                    env.voices.rename(target.id, to: renameText)
                }
                renameTarget = nil
            }
        }
        .task {
            #if DEBUG
            DebugHarness.autopilot(in: lab) { }
            tab = DebugHarness.voiceTab
            if DebugHarness.action == "voice-edit" {
                editingVoice = env.voices.selectedVoice
            }
            #endif
        }
    }

    // MARK: - 演绎
    // 「演绎指令」已移除：它和声线描述是同一个通道，混在一起写反而让音色漂。
    // 现在所有对声音的调整都收敛到「编辑声线 → 提示词」与两条参数上。

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "参数")

            sliderRow("全局语速", value: $vm.speed, range: 0.7...1.3, step: 0.05,
                      hint: "0.7 偏慢 · 1.05 自然 · 1.3 偏快")

            sliderRow("指导强度 cfg_scale", value: $vm.guidanceScale,
                      range: AppConfig.guidanceRange, step: 0.1,
                      hint: "1.0 自然 · 2~3 令 [笑] / (cough) 生效 · 超过 3 发刺")
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).tint(Theme.controlTint)
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 内置

    private var builtinTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "五条内置声线")

            ForEach(env.voices.builtinVoices) { voice in
                voiceRow(voice, deletable: false)
            }

            Text("内置声线与「文字造声」走同一条通路：用固定的英文声音描述造出稳定音色，不需要额外权重。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - 克隆

    private var cloneTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "参考音频",
                         trailing: AnyView(Pill(text: "\(env.voices.cloneSlotsLeft) 个空位")))

            // 现场录音：录完自动本地转写原文并提取声纹，不用打一个字
            HStack(spacing: 8) {
                Button {
                    lab.toggleRecording()
                } label: {
                    if lab.isRecording {
                        Label("停止 · \(lab.recorder.formattedElapsed)", systemImage: "stop.circle.fill")
                    } else {
                        Label(lab.isTranscribing ? "本地识别中…" : "对着 iPad 说 5~30 秒话",
                              systemImage: "mic.circle")
                    }
                }
                .primaryPill()
                .disabled(lab.isTranscribing || lab.isAnalyzing)
                .opacity(lab.isRecording ? 1 : (lab.isTranscribing ? 0.55 : 1))

                if lab.isTranscribing {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                    Text("识别原文中，全离线")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    showImporter = true
                } label: {
                    Label(lab.importFileName.isEmpty ? "或导入 wav / m4a" : lab.importFileName,
                          systemImage: "waveform.badge.plus")
                        .lineLimit(1)
                }
                .quietPill()

                if !lab.importFileName.isEmpty {
                    Pill(text: "已就绪")
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "参考音频原话")
                TextEditor(text: $lab.referenceText)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .frame(height: 54)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.faintFill))
                Text(lab.transcribedFromRecording
                     ? "原文由本机语音识别自动填入，可手动微调后再提取。"
                     : "现场录音会自动识别原文；导入文件时需要手动填写逐字原话，否则声纹会对不上。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "文字微调（可选）")
                TextField("例：语速稍慢、语气更温柔；留空就完全按参考音频来", text: $lab.cloneTweak)
                    .font(.system(size: 12.5))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.faintFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                Text("参考音频决定「是谁」，这段话只调语气、语速、气息，不动音高。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await lab.extractClone() }
                } label: {
                    if lab.isAnalyzing {
                        Label("提取中…", systemImage: "hourglass")
                    } else {
                        Label("提取声纹", systemImage: "waveform.path.ecg")
                    }
                }
                .primaryPill()
                .disabled(lab.isAnalyzing || lab.importURL == nil)

                if let analysis = lab.analysis {
                    Text(String(format: "%.1fs · SNR %.0f dB", analysis.duration, analysis.snr))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ForEach(lab.issues) { issue in
                HStack(spacing: 6) {
                    Image(systemName: issue.isBlocking ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.system(size: 9.5))
                    Text(issue.message)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(issue.isBlocking ? Color.primary : Color.secondary)
            }

            if lab.draftClone != nil {
                draftCard(name: $lab.cloneName,
                          subtitle: "声纹已提取并缓存，命名后存入声线库",
                          canSave: true,
                          onSave: { _ = lab.saveDraftClone() },
                          onDiscard: { lab.resetCloneDraft() })
            }

            if !env.voices.cloneVoices.isEmpty {
                Divider().opacity(0.4)
                SectionLabel(text: "已保存的克隆")
                ForEach(env.voices.cloneVoices) { voice in
                    voiceRow(voice, deletable: true)
                }
            }
        }
    }

    // MARK: - 造声

    private var designTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 名称与提示词是这一页的主角，放大、加框、单独成块
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(text: "名称")
                TextField("给这条声线起个名字", text: $lab.designName)
                    .font(.system(size: 17, weight: .semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.faintFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("提示词")
                        .font(.system(size: 15, weight: .semibold))
                    Pill(text: "决定音色")
                    Spacer(minLength: 0)
                    Text("\(lab.designDescription.count) 字")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $lab.designDescription)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .frame(height: 118)
                        .padding(7)

                    if lab.designDescription.isEmpty {
                        Text("年龄、性别、音色、沙哑或清亮、气息、口音风格。\n例：三十岁女性，中低音，略带沙哑，气息偏弱，深夜电台感。")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.faintFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

                Text("描述写的是「这个人」，不是「这句话」。写成同一个人，换文字才是同一个声音。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            sliderRow("指导强度 guidance", value: $lab.designGuidance, range: 1...6, step: 0.1,
                      hint: "1 宽松 · 4 默认 · 6 严格贴合描述")

            Button {
                Task { await lab.createDesign() }
            } label: {
                if lab.isDesigning {
                    Label("生成中…", systemImage: "hourglass")
                } else {
                    Label("生成全新声线", systemImage: "sparkles")
                }
            }
            .primaryPill()
            .disabled(lab.isDesigning || lab.designDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if lab.draftDesign != nil {
                draftCard(name: $lab.designName,
                          subtitle: "声线已生成，确认名称后存入声线库",
                          showsNameField: false,
                          canSave: true,
                          onSave: { _ = lab.saveDraftDesign() },
                          onDiscard: { lab.draftDesign = nil })
            }

            if !env.voices.designVoices.isEmpty {
                Divider().opacity(0.4)
                SectionLabel(text: "已保存的造声")
                ForEach(env.voices.designVoices) { voice in
                    voiceRow(voice, deletable: true)
                }
            }
        }
    }

    // MARK: - 复用组件

    @ViewBuilder
    private func draftCard(name: Binding<String>,
                           subtitle: String,
                           showsNameField: Bool = true,
                           canSave: Bool,
                           onSave: @escaping () -> Void,
                           onDiscard: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("新声线").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if showsNameField {
                TextField("给它起个名字", text: name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.faintFill))
            }

            HStack(spacing: 8) {
                Button("保存到声线库") { onSave() }
                    .primaryPill()
                    .disabled(!canSave)
                Button("重新开始") { onDiscard() }
                    .quietPill()
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.softFill))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }

    private func voiceRow(_ voice: VoiceProfile, deletable: Bool) -> some View {
        let selected = env.voices.selectedVoiceID == voice.id
        let isDefault = env.voices.isDefault(voice.id)

        return HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.primary : Color.secondary.opacity(0.45))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(voice.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if isDefault { Pill(text: "默认", emphasis: true) }
                }
                Text(voice.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                editingVoice = voice
            } label: {
                Text("编辑")
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                Task { await lab.preview(voice) }
            } label: {
                Image(systemName: lab.previewingVoiceID == voice.id ? "hourglass" : "play.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(lab.previewingVoiceID != nil)

            if deletable {
                Button {
                    env.voices.delete(voice.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Theme.softFill : Theme.faintFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.primary.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            vm.applyVoice(voice)
            Haptics.light()
        }
        .contextMenu {
            Button("设为默认") { env.voices.setDefault(voice.id) }
            Button("重命名") {
                renameTarget = voice
                renameText = voice.displayName
            }
            if deletable {
                Button("删除", role: .destructive) { env.voices.delete(voice.id) }
            }
        }
    }
}
