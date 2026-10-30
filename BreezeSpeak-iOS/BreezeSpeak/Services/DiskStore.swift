//
//  DiskStore.swift
//  BreezeSpeak
//
//  轻量 JSON 持久化。所有数据都落在沙盒内，无任何网络端口。
//

import Foundation

enum DiskStore {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        AppPaths.ensure(url.deletingLastPathComponent())
        guard let data = try? encoder.encode(value) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
