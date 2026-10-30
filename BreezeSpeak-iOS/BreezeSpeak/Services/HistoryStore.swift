//
//  HistoryStore.swift
//  BreezeSpeak
//
//  音频历史：保存文本、声线、演绎参数与 WAV 文件，支持重听 / 复用 / 删除。
//

import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryRecord] = []

    init() {
        reload()
    }

    func reload() {
        items = DiskStore.load([HistoryRecord].self, from: AppPaths.historyFile) ?? []
        pruneMissingFiles()
    }

    @discardableResult
    func add(
        text: String,
        voice: VoiceProfile,
        direction: String,
        guidance: Double,
        speed: Double,
        result: TTSResult,
        engineName: String
    ) -> HistoryRecord? {
        let id = UUID()
        let fileName = "\(id.uuidString).wav"
        let url = AppPaths.audioDirectory.appendingPathComponent(fileName)
        guard WAVFile.write(samples: result.samples, sampleRate: result.sampleRate, to: url) else { return nil }

        let record = HistoryRecord(
            id: id,
            text: text,
            voiceID: voice.id,
            voiceName: voice.displayName,
            voiceKind: voice.kind,
            spk: voice.spk,
            direction: direction,
            guidance: guidance,
            speed: speed,
            fileName: fileName,
            duration: result.duration,
            sampleRate: result.sampleRate,
            peaks: AudioAnalysis.peaks(from: result.samples, count: 96),
            engineName: engineName
        )

        items.insert(record, at: 0)
        if items.count > AppConfig.maxHistoryItems {
            for stale in items.suffix(from: AppConfig.maxHistoryItems) {
                DiskStore.remove(stale.fileURL)
            }
            items = Array(items.prefix(AppConfig.maxHistoryItems))
        }
        persist()
        return record
    }

    func delete(_ record: HistoryRecord) {
        DiskStore.remove(record.fileURL)
        items.removeAll { $0.id == record.id }
        persist()
    }

    func clearAll() {
        for record in items { DiskStore.remove(record.fileURL) }
        items.removeAll()
        persist()
        // 顺手清掉目录里可能残留的孤儿文件
        if let files = try? FileManager.default.contentsOfDirectory(at: AppPaths.audioDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "wav" {
                DiskStore.remove(file)
            }
        }
    }

    func record(id: UUID) -> HistoryRecord? {
        items.first(where: { $0.id == id })
    }

    var totalDuration: Double { items.reduce(0) { $0 + $1.duration } }

    private func pruneMissingFiles() {
        let filtered = items.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        if filtered.count != items.count {
            items = filtered
            persist()
        }
    }

    private func persist() {
        DiskStore.save(items, to: AppPaths.historyFile)
    }
}
