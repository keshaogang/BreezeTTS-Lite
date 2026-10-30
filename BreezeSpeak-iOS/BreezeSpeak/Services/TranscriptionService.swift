//
//  TranscriptionService.swift
//  BreezeSpeak
//
//  参考音频的本地转写：用 Apple Speech 框架把录音变成逐字文稿，
//  让克隆流程不需要手动输入参考文字。
//
//  优先强制 on-device 识别（requiresOnDeviceRecognition），全程离线；
//  个别机型 / 模拟器不支持离线中文时才退回服务器通道，App 内会有明确提示。
//

import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case unavailable
    case denied
    case empty
    case timeout

    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前设备不支持语音识别"
        case .denied: return "语音识别权限未开启，请到「设置 → BreezeSpeak」里允许"
        case .empty: return "没听清内容，请靠近一点、安静环境下再录一次"
        case .timeout: return "识别超时，请换一段更短的音频"
        }
    }
}

enum TranscriptionService {

    // MARK: 权限

    static func authorize() async throws {
        let mic = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard mic else { throw TranscriptionError.denied }

        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else { throw TranscriptionError.denied }
    }

    // MARK: 转写

    /// 把一段音频转成文字。优先离线识别；中文离线包缺失时自动走在线通道。
    static func transcribe(url: URL) async throws -> String {
        try await authorize()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var lastText = ""

            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }

                if let result {
                    lastText = result.bestTranscription.formattedString
                    if result.isFinal {
                        finished = true
                        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: text)
                    }
                }

                if let error {
                    finished = true
                    // 识别中途出错但已有可用文本，就用已有文本，别让用户白录一遍
                    if !lastText.isEmpty {
                        continuation.resume(returning: lastText.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }

            // 最长等 45 秒；超时但有部分文本也算成功
            DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
                guard !finished else { return }
                finished = true
                task.finish()
                if !lastText.isEmpty {
                    continuation.resume(returning: lastText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: TranscriptionError.timeout)
                }
            }
        }
    }
}
