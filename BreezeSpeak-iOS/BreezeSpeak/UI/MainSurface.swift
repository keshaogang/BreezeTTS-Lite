//
//  MainSurface.swift
//  BreezeSpeak
//
//  与 macOS 版一致的主界面：一块书写面 + 一条悬浮玻璃工具栏。
//  音色、历史、模型、设置全部收进弹窗，窗口本身不堆面板。
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vm: SynthesisViewModel

    @FocusState private var editorFocused: Bool
    @StateObject private var keyboard = KeyboardObserver()
    /// 底部工具栏实际占的高度（含上下 padding 与键盘高度），由工具栏自己量出来
    @State private var toolbarReserve: CGFloat = 0

    var body: some View {
        // 布局原则：顶部永不受键盘影响。
        //
        // 之前工具栏用 `.safeAreaInset(edge: .bottom)` 挂上去，键盘一弹，安全区被改写，
        // 整个视图树重新参与一次「撑高 / 居中」的协商，结果就是内容整体被顶偏十几到几十点，
        // 看起来正是「一开输入法界面就往下跳」。
        // 现在改成：内容区高度自己算（减去工具栏占位），工具栏用 overlay 浮在底部。
        // 键盘高度只影响「内容底部让出多少」，不触发任何安全区协商，顶部因此是钉死的。
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 22)
                        .padding(.top, 14)

                    editor
                        .padding(.horizontal, 32)
                        .padding(.top, 26)

                    footer
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                }
                .frame(width: proxy.size.width,
                       height: max(0, proxy.size.height - toolbarReserve),
                       alignment: .top)
                #if DEBUG
                .onAppear {
                    KBSnap.layoutNote = "geo \(proxy.size) reserve \(toolbarReserve) safe \(proxy.safeAreaInsets)"
                }
                .onChangeCompat(of: proxy.size) { _, size in
                    KBSnap.layoutNote = "geo \(size) reserve \(toolbarReserve) safe \(proxy.safeAreaInsets)"
                }
                #endif
            }
        }
        // 键盘安全区自己接管：
        //   · 贴底全屏键盘 → 工具栏按键盘高度整体上移；
        //   · 悬浮 / 拆分键盘 → 它只是块浮窗，工具栏留在原位，页面不为它让位；
        //   · 外接键盘 → 没有软件键盘，什么都不用动。
        .overlay(alignment: .bottom) {
            toolbar
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 14 + keyboard.dockedHeight)
                .animation(.easeOut(duration: 0.2), value: keyboard.dockedHeight)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ToolbarHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .onPreferenceChange(ToolbarHeightKey.self) { toolbarReserve = $0 }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChangeCompat(of: vm.text) { old, new in
            // 回车即发送：TextEditor 没有 onSubmit，只能在文本变化里截住那个换行。
            // 只在「刚好多出一个字符且就是换行」时触发，避免粘贴整段带换行的文本被误发。
            guard vm.submitOnReturn, new.count == old.count + 1, new.hasSuffix("\n") else { return }
            vm.text = String(new.dropLast())
            if vm.canGenerate { vm.generate() }
        }
        .onChangeCompat(of: env.model.status) { _, status in
            env.runtime.refresh()
            // 权重一下好就预热，第一次点生成不用等加载
            if case .ready = status { env.warmUp() }
        }
        // 从桌面小组件点「开始朗读」进来：直接把光标放进正文
        .onChangeCompat(of: vm.composeToken) { _, _ in
            editorFocused = true
        }
        .task {
            #if DEBUG
            // 键盘布局走查：-demo focus-editor 直接聚焦正文，好把键盘调出来截图
            if DebugHarness.action == "focus-editor" {
                try? await Task.sleep(nanoseconds: 700_000_000)
                editorFocused = true
            }
            #endif
        }
        .sheet(isPresented: $vm.showVoiceLibrary) {
            VoiceSheet(lab: VoiceLabModel(voices: env.voices, player: env.player, runtime: env.runtime))
                .environmentObject(env)
                .environmentObject(vm)
                .pageSheetSizing()
                .sheetCanvasBackground(Theme.canvas)
        }
        .sheet(isPresented: $vm.showHistory) {
            HistorySheet()
                .environmentObject(env)
                .environmentObject(vm)
                .pageSheetSizing()
                .sheetCanvasBackground(Theme.canvas)
        }
        .sheet(isPresented: $vm.showModelSheet) {
            ModelSheet()
                .environmentObject(env)
                .environmentObject(vm)
                .pageSheetSizing()
                .sheetCanvasBackground(Theme.canvas)
        }
        .sheet(isPresented: $vm.showSettings) {
            SettingsSheet()
                .environmentObject(env)
                .environmentObject(vm)
                .pageSheetSizing()
                .sheetCanvasBackground(Theme.canvas)
        }
        .alert(item: $vm.alert) { payload in
            Alert(
                title: Text(payload.title),
                message: Text(payload.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .fileExporter(
            isPresented: $vm.showExportPicker,
            document: vm.exportDocument ?? WAVDocument(data: Data()),
            contentType: .wav,
            defaultFilename: vm.exportFileName
        ) { result in
            switch result {
            case .success(let url):
                vm.showToast("已保存到「文件」：\(url.lastPathComponent)")
            case .failure(let error):
                vm.alert = AlertPayload(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("BREEZE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Button {
                vm.showModelSheet = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(env.model.isReady ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(modelLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .contentShape(Capsule())
                .glassCapsule()
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button { vm.showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .glassIconButton()

            Button { vm.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .glassIconButton()
        }
        .frame(height: 32)
    }

    private var modelLabel: String {
        if env.model.isDownloading {
            return "下载中 \(Int(env.model.progress * 100))%"
        }
        if env.model.isReady { return env.model.selectedTier.shortName }
        return "模型未就绪"
    }

    // MARK: - 编辑区

    private var editor: some View {
        // 用 GeometryReader 包一层：TextEditor 自带一个不小的固有高度，
        // 键盘把可用高度压到很小时它不肯继续缩，整块内容就会溢出可用区域、
        // 被整体顶偏（看起来就是「一开键盘内容往下跳」）。包一层后它接受任何尺寸。
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.text)
                    .font(.system(size: 17))
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .scrollDismissesKeyboard(.interactively)
                    .padding(.horizontal, -4)

                if vm.text.isEmpty {
                    Text("写点什么，或者粘贴一段文字。\n支持 | 短停顿、|| 长停顿、(slow) (fast) (whisper)、[笑] 等标记。")
                        .font(.system(size: 17))
                        .lineSpacing(7)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        // 显式抢焦点：个别情况下（外部键盘配对过、手势被浮层吃掉）
        // TextEditor 自带的点击聚焦会失效，这里兜底一次。
        .onTapGesture { editorFocused = true }
        .frame(maxWidth: 700, maxHeight: .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
        // 「收起键盘」放在底部工具栏里，跟着 keyboard.isVisible 出现：
        // 外接键盘 / 悬浮键盘收起时它不该占位置，也不该出现在键盘工具条上。
    }

    // MARK: - 页脚

    private var footer: some View {
        HStack(spacing: 10) {
            Text(vm.text.isEmpty ? " " : "\(vm.characterCount) 字")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            if let estimate = vm.estimateLabel {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9, weight: .medium))
                    Text(estimate)
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
                .transition(.opacity)
            }

            Spacer(minLength: 8)

            if vm.isGenerating || vm.player.isPlaying {
                LevelMeter(level: vm.isGenerating ? 0.55 : playbackLevel, bars: 18)
                    .frame(height: 16)
            }

            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var statusText: String {
        // 提示信息占用同一行，避免浮层压住页脚
        if let toast = vm.toast { return toast }
        if vm.isGenerating {
            if let remaining = vm.remainingLabel {
                return "合成中 \(Int(vm.progress * 100))% · 剩\(remaining)"
            }
            return "合成中 \(Int(vm.progress * 100))%"
        }
        if vm.player.duration > 0 {
            return "\(TimeFormat.mmss(vm.player.duration)) · \(vm.engineLabel)"
        }
        return vm.isNeural ? "\(vm.engineLabel) · 本机推理" : "\(vm.engineLabel) · 兜底模式"
    }

    private var playbackLevel: Float {
        let peaks = vm.player.peaks
        guard !peaks.isEmpty else { return 0 }
        let position = min(1, max(0, vm.player.progress))
        let index = Int(position * Double(peaks.count - 1))
        let window = peaks[max(0, index - 2)...min(peaks.count - 1, index + 2)]
        return min(1, (window.max() ?? 0) * 3)
    }

    // MARK: - 悬浮工具栏

    private var toolbar: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 5) {
                Button {
                    vm.showVoiceLibrary = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.wave.2")
                            .font(.system(size: 12, weight: .medium))
                        Text(env.voices.selectedVoice.displayName)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                hairline

                Button {
                    if vm.isGenerating { vm.cancel() } else { vm.generate() }
                } label: {
                    let active = vm.canGenerate || vm.isGenerating
                    HStack(spacing: 7) {
                        if vm.isGenerating {
                            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "waveform").font(.system(size: 11, weight: .bold))
                        }
                        Text(vm.isGenerating ? "停止" : "生成")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(active ? Theme.inverse : Color.primary.opacity(0.42))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    // 给胶囊上色：外面那条工具栏是中性玻璃，这颗是染深的玻璃，
                    // 两层玻璃贴在一起时系统还会让它们互相吸附。
                    .glassCapsule(tint: Color.primary.opacity(active ? 0.88 : 0.16))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canGenerate && !vm.isGenerating)

                if hasAudio && !vm.isGenerating {
                    hairline

                    Button { vm.playPause() } label: {
                        Image(systemName: vm.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.05))
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    PlaybackTrack(progress: vm.player.progress) { value in
                        vm.player.seek(to: value * vm.player.duration)
                    }
                    .frame(width: 64, height: 18)

                    Text(TimeFormat.mmss(vm.player.currentTime))
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                if hasAudio {
                    hairline
                    glyphButton("square.and.arrow.down") { vm.exportWAV() }
                }

                AirPlayRoutePicker(tint: .secondary)
                    .frame(width: 18, height: 18)
                    .frame(width: 28, height: 28)

                if keyboard.isVisible {
                    hairline
                    glyphButton("keyboard.chevron.compact.down") { editorFocused = false }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassCapsule()
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: hasAudio)
    }

    private var hasAudio: Bool {
        vm.lastResult != nil || vm.player.duration > 0
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }

    private func glyphButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.faintFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toast

    /// 提示统一走页脚状态行，不再叠一层浮层
}

/// 细长的进度条：点或拖都能定位。
struct PlaybackTrack: View {
    var progress: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let filled = max(3, width * min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: width, height: 3)
                Capsule()
                    .fill(Color.primary.opacity(0.78))
                    .frame(width: filled, height: 3)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
                    .offset(x: min(max(0, filled - 3.5), width - 7))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(min(1, max(0, value.location.x / width)))
                    }
            )
        }
    }
}

// MARK: - 工具栏高度

/// 把工具栏的实际高度往上递，内容区据此让出底部空间。
struct ToolbarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
