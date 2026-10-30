//
//  WidgetCards.swift
//  BreezeSpeak 小组件版式
//
//  每个尺寸一个独立的卡片视图，App 内可用离屏渲染逐张检查。
//

import SwiftUI

// MARK: - 桌面 · 小

/// 一屏只放得下一件事：告诉你这是什么，然后让你点进去开始。
struct HomeSmallCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetWaveform(barWidth: 2.5, gap: 2.5, maxHeight: 17)

            Spacer(minLength: 6)

            Text("BreezeSpeak")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(WidgetInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("本机离线 · 不上传")
                .font(.system(size: 9.5))
                .foregroundStyle(WidgetInk.tertiary)
                .lineLimit(1)
                .padding(.top, 2)

            Spacer(minLength: 8)

            Link(destination: WidgetLink.compose.url) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10, weight: .semibold))
                    Text("开始朗读")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(WidgetInk.paper)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(WidgetInk.ink))
            }
            .buttonStyle(.plain)
        }
        // 撑满再顶部对齐：不然 VStack 只有理想宽度，外面一 frame 就整体居中，
        // 波形和标题会跑到卡片中间去。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 桌面 · 中

/// 左边立品牌，右边三个入口：一眼知道能做什么，点哪进哪。
struct HomeMediumCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetWaveform(barWidth: 2.5, gap: 2.5, maxHeight: 16)

                Spacer(minLength: 8)

                Text("Breeze\nSpeak")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetInk.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Text("文字不出设备")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WidgetInk.tertiary)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 6) {
                WidgetEntry(icon: "square.and.pencil", title: "新建朗读",
                            detail: "写下来，直接生成", link: .compose)
                WidgetEntry(icon: "person.wave.2", title: "声线库",
                            detail: "内置 + 克隆", link: .voices)
                WidgetEntry(icon: "clock.arrow.circlepath", title: "最近生成",
                            detail: "回听与导出", link: .history)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 桌面 · 大

/// 在「中」的基础上补一张标记速查：停顿符号是这 App 最容易被忘掉的东西。
struct HomeWideCard: View {
    private let marks: [(String, String)] = [
        ("|", "停半拍"),
        ("||", "停一拍"),
        ("(whisper)", "耳语"),
        ("(slow)", "放慢")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 给一个确定高度：中号卡片内部有 Spacer，放进大号后被拉高，
            // 会把「文字不出设备」推到半空去。
            HomeMediumCard()
                .frame(height: 122)
                .padding(.bottom, 14)

            Divider()
                .overlay(WidgetInk.hairline)
                .padding(.bottom, 12)

            Text("停顿与语气标记")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetInk.secondary)
                .padding(.bottom, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(marks, id: \.0) { mark, meaning in
                    HStack(spacing: 7) {
                        Text(mark)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(WidgetInk.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(WidgetInk.fill)
                            )
                        Text(meaning)
                            .font(.system(size: 10))
                            .foregroundStyle(WidgetInk.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 14)

            Divider()
                .overlay(WidgetInk.hairline)
                .padding(.bottom, 12)

            Text("三步")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetInk.secondary)
                .padding(.bottom, 7)

            VStack(alignment: .leading, spacing: 7) {
                step("1", "写下来", "在想停的地方打 | 或 ||")
                step("2", "点生成", "短句几秒，长文自动分段")
                step("3", "听或存", "底栏播放，右下角存成 WAV")
            }

            Spacer(minLength: 10)

            Link(destination: WidgetLink.compose.url) {
                HStack(spacing: 6) {
                    Text("写一段试试")
                        .font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(WidgetInk.ink)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetInk.secondary)
                .frame(width: 14, height: 14)
                .background(Circle().fill(WidgetInk.fill))

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetInk.ink)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(WidgetInk.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 锁屏 · 圆形

/// 只画内容，圆形底色由扩展侧用系统的 AccessoryWidgetBackground 铺，
/// 共享层不引入 WidgetKit，这样 App 里也能编译这一份做离屏自查。
struct LockCircleCard: View {
    var body: some View {
        VStack(spacing: 2) {
            WidgetWaveform(bars: [0.45, 0.85, 1.0, 0.6],
                           barWidth: 2.2, gap: 2, maxHeight: 13)
            Text("朗读")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(WidgetInk.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 锁屏 · 矩形

struct LockRectCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            WidgetWaveform(bars: [0.35, 0.7, 1.0, 0.55],
                           barWidth: 2.4, gap: 2.4, maxHeight: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("BreezeSpeak")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetInk.ink)
                Text("点按开始朗读，全部在本机")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WidgetInk.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 锁屏 · 行内

struct LockInlineCard: View {
    var body: some View {
        Text("BreezeSpeak · 离线朗读")
    }
}
