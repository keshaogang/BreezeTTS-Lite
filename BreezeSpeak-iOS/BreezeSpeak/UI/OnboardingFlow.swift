//
//  OnboardingFlow.swift
//  BreezeSpeak
//
//  首次启动的四步：介绍 → 免责协议 → 选择模型 → 开始使用。
//  语气与配色沿用主界面的单色语言：不做插画、不做渐变，只把该说清楚的事说清楚。
//

import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var model: ModelManager

    /// 走完流程的回调，由 App 层把引导换成交互界面
    var onFinish: () -> Void

    @State private var step: Int = 0
    @State private var accepted = false

    /// 截图专用：ImageRenderer 渲染不出 ScrollView 里的内容，走查版式时
    /// 换成不退滚的 VStack。正常运行时始终为 false。
    private var snapshotMode = false

    private let stepCount = 4

    init(startStep: Int = 0, snapshotMode: Bool = false, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        self.snapshotMode = snapshotMode
        _step = State(initialValue: max(0, min(3, startStep)))
        // 上次已经同意过协议（走完引导前退出了），回来就别再勾一次
        _accepted = State(initialValue: OnboardingState.hasAcceptedDisclaimer)
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if snapshotMode {
                    stepContent
                        .padding(.horizontal, 28)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .top)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        stepContent
                            .padding(.horizontal, 28)
                            .padding(.top, 6)
                            .padding(.bottom, 28)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                    }
                }

                footer
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Theme.controlTint)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: disclaimerStep
        case 2: modelStep
        default: readyStep
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    go(to: step - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.primary.opacity(0.75) : Color.primary.opacity(0.14))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: step)

            Spacer(minLength: 8)

            Text("BREEZE")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 34)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    // MARK: - 第一步：介绍

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text("把文字\n读成声音")
                    .font(.system(size: 38, weight: .semibold))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("BreezeSpeak 在一台 iPad 上完成全部语音合成。写完点一下，几秒后就能听，也能存成 WAV。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 18)

            VStack(spacing: 0) {
                feature(icon: "waveform",
                        title: "全程在本机推理",
                        detail: "文字与音频都不出设备，飞行模式照常工作。")
                divider
                feature(icon: "person.wave.2",
                        title: "一句话造一个音色",
                        detail: "写出性别、年龄、语气，或者录一段参考音频复刻。")
                divider
                feature(icon: "square.and.arrow.down",
                        title: "生成的文件归你",
                        detail: "WAV 直接存进「文件」App，拿去剪辑或配音都行。")
            }
            .glassCard(cornerRadius: 20)

            Text("首次使用需要下载一次模型权重（约 2.4 GB）。下载完就可以断网使用，之后不再需要网络。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.faintFill))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, 64)
    }

    // MARK: - 第二步：免责协议

    private var disclaimerStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("使用须知")
                    .font(.system(size: 26, weight: .semibold))
                Text("声音可以很有力量，所以先把边界说清楚。读完再开始。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 16) {
                clause("仅限合法用途",
                       "请勿用本应用制作违法内容，或伪造他人声音、制造虚假信息、冒充他人身份。")
                clause("声音克隆需要授权",
                       "只克隆自己的声音，或已经获得明确书面授权的声音。公开发布 AI 生成的音频，请依法显著标识。")
                clause("内容责任自负",
                       "你输入的文本、创建的音色、生成的音频，以及由此产生的一切后果，都由你本人承担。")
                clause("按现状提供",
                       "本应用为个人学习与研究用途，按「现状」提供，不附带任何担保，使用风险自负。")
                clause("侵权告知即下架",
                       "若权利人认为本项目侵犯其权益，可通过项目仓库的 Issues 提出并附权属证明，核实后 72 小时内下架。")
            }

            Button {
                accepted.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: accepted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(accepted ? Color.primary : Color.primary.opacity(0.35))
                    Text("我已阅读并同意以上条款，且知悉声音克隆须获得授权")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accepted ? Theme.softFill : Theme.faintFill)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.16), value: accepted)

            Text("不同意以上条款请直接关闭应用。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
    }

    private func clause(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 第三步：模型

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("选择模型")
                    .font(.system(size: 26, weight: .semibold))
                Text("权重只下载一次。档位之间能力完全一致，区别只在音质细节与内存占用。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)

            VStack(spacing: 8) {
                ForEach(ModelTiers.all) { tier in
                    tierRow(tier)
                }
            }

            downloadPanel

            Text("下载支持断点续传，中途退出下次接着来。全部数据都在 App 沙盒内。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierRow(_ tier: ModelTier) -> some View {
        let selected = tier.id == model.selectedTierID
        let recommended = model.isRecommended(tier)

        return Button {
            model.select(tierID: tier.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.25))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tier.name)
                            .font(.system(size: 12.5, weight: .medium))
                        if tier.installed { Pill(text: "已下载") }
                        if recommended { Pill(text: "推荐") }
                        Spacer(minLength: 0)
                    }
                    Text(tier.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(tier.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Theme.softFill : Theme.faintFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var downloadPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isReady {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("已缓存到本机 · 断网也能用")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(.primary)
            } else {
                bar(model.progress)

                HStack(spacing: 8) {
                    Text(model.isDownloading
                         ? "\(Int(model.progress * 100))% · \(TimeFormat.bytes(model.downloadedBytes)) / \(TimeFormat.bytes(model.totalBytes))"
                         : "待下载 · 共 \(TimeFormat.bytes(model.totalBytes))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    if model.isDownloading && model.speed > 0 {
                        Text(String(format: "%.1f MB/s", model.speed / 1_048_576))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    if model.isDownloading {
                        Button {
                            model.cancelDownload()
                        } label: {
                            Text("暂停")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            model.downloadIfNeeded()
                        } label: {
                            Text(model.downloadedBytes > 0 ? "继续" : "开始下载")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = model.lastError, !model.isDownloading {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.faintFill)
        )
    }

    private func bar(_ value: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: max(2, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 4)
    }

    // MARK: - 第四步：开始使用

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("可以开始了")
                    .font(.system(size: 30, weight: .semibold))
                    .padding(.top, 30)
                Text("下面三个动作会伴随你之后每一次使用。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                tip(number: "1", title: "写下来",
                    detail: "在想停的地方打 | 停半拍，打 || 停一拍；括号里写 (slow)、(whisper) 可以改这一句的语气。")
                divider
                tip(number: "2", title: "点生成",
                    detail: "短句几秒就出来；长文会自动分段合成，接缝处音色保持一致。")
                divider
                tip(number: "3", title: "听或存",
                    detail: "底栏直接播放，右下角按钮存成 WAV，文件在「文件 → 我的 iPad → BreezeSpeak」。")
            }
            .glassCard(cornerRadius: 20)
        }
    }

    private func tip(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.faintFill))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 底栏

    private var footer: some View {
        VStack(spacing: 8) {
            switch step {
            case 0:
                primaryButton("开始") { go(to: 1) }
            case 1:
                primaryButton("同意并继续", enabled: accepted) {
                    OnboardingState.acceptDisclaimer()
                    go(to: 2)
                }
            case 2:
                primaryButton(model.isReady ? "下一步" : (model.isDownloading ? "下载中…" : "下一步")) {
                    go(to: 3)
                }
                if !model.isReady {
                    Button {
                        if !model.isDownloading {
                            model.downloadIfNeeded()
                        }
                        go(to: 3)
                    } label: {
                        Text("先跳过，稍后下载")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            default:
                primaryButton("进入 BreezeSpeak") {
                    OnboardingState.complete()
                    onFinish()
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .frame(maxWidth: 620)
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                // 禁用态用弱化主色而不是反色：反色在浅底上几乎看不见
                .foregroundStyle(enabled ? Theme.inverse : Color.primary.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(enabled ? 1 : 0.10))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - 步进

    private func go(to next: Int) {
        withAnimation(.easeInOut(duration: 0.24)) {
            step = max(0, min(stepCount - 1, next))
        }
    }
}
