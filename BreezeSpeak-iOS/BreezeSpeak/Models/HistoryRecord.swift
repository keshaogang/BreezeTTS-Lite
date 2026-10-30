//
//  HistoryRecord.swift
//  BreezeSpeak
//

import Foundation

struct HistoryRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var voiceID: UUID
    var voiceName: String
    var voiceKind: VoiceKind
    var spk: String?
    var direction: String = ""
    var guidance: Double
    var speed: Double
    var fileName: String
    var duration: Double
    var sampleRate: Double
    var peaks: [Float] = []
    var engineName: String = ""
    var createdAt: Date = Date()

    var fileURL: URL { AppPaths.audioDirectory.appendingPathComponent(fileName) }

    var previewText: String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count > 48 ? String(flattened.prefix(48)) + "…" : flattened
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
