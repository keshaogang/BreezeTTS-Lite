//
//  HistorySheet.swift
//  BreezeSpeak
//
//  历史：每一条都保存了文本、声线、演绎参数与 WAV 文件。
//  支持重听、导出到「文件」、用原参数重新生成、删除。
//

import SwiftUI

struct HistorySheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vm: SynthesisViewModel

    var body: some View {
        SheetChrome(title: "历史",
                    subtitle: historySubtitle,
                    trailing: env.history.items.isEmpty ? nil : AnyView(
                        Button("清空") { env.history.clearAll() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    )) {
            if env.history.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("生成的音频会留在这里")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 120)
            } else {
                VStack(spacing: 6) {
                    ForEach(env.history.items) { item in
                        row(item)
                    }
                }
            }
        }
    }

    private var historySubtitle: String {
        guard !env.history.items.isEmpty else { return "还没有记录" }
        return "\(env.history.items.count) 条 · 共 \(TimeFormat.mmss(env.history.totalDuration))"
    }

    private func row(_ item: HistoryRecord) -> some View {
        let isCurrent = vm.lastRecord?.id == item.id
        let isPlaying = isCurrent && vm.player.isPlaying

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    vm.play(record: item)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(isCurrent ? 0.16 : 0.08)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.previewText)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("\(item.voiceName) · \(item.relativeTime) · \(TimeFormat.mmss(item.duration))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                Button {
                    vm.exportFile(at: item.fileURL)
                } label: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    vm.reuseHistory(item)
                    vm.showHistory = false
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    env.history.delete(item)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if !item.direction.isEmpty {
                Text("演绎：\(item.direction)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.faintFill)
        )
        .onTapGesture {
            vm.play(record: item)
        }
    }
}
