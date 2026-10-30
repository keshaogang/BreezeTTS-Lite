//
//  WAVFile.swift
//  BreezeSpeak
//
//  16-bit PCM WAV 读写（导出到「文件」App 也用它）。
//

import Foundation
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum WAVFile {
    static let headerBytes = 44

    static func data(samples: [Float], sampleRate: Double) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let riffSize = dataSize + 36

        var data = Data(capacity: headerBytes + samples.count * 2)

        func append(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(riffSize)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)                       // PCM
        append16(channels)
        append32(UInt32(sampleRate))
        append32(byteRate)
        append16(blockAlign)
        append16(bitsPerSample)
        append("data")
        append32(dataSize)

        var pcm = [Int16](repeating: 0, count: samples.count)
        for (index, sample) in samples.enumerated() {
            let clamped = max(-1, min(1, sample))
            pcm[index] = Int16(clamped * 32_767)
        }
        pcm.withUnsafeBytes { raw in
            data.append(contentsOf: raw)
        }
        return data
    }

    @discardableResult
    static func write(samples: [Float], sampleRate: Double, to url: URL) -> Bool {
        AppPaths.ensure(url.deletingLastPathComponent())
        do {
            try data(samples: samples, sampleRate: sampleRate).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 读取任意系统可解码的音频（wav / m4a / mp3…），下混为单声道 Float 并重采样到模型采样率。
    static func read(url: URL) throws -> TTSResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frames = AVAudioFrameCount(file.length)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                throw TTSError.audioUnreadable("音频为空")
            }
            try file.read(into: buffer)
            let mono = AudioMath.monoSamples(from: buffer)
            let resampled = AudioMath.resample(mono, from: format.sampleRate, to: AppConfig.sampleRate)
            return TTSResult(samples: resampled, sampleRate: AppConfig.sampleRate)
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.audioUnreadable(error.localizedDescription)
        }
    }
}

// MARK: - 导出文档

import SwiftUI
import UniformTypeIdentifiers

struct WAVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
