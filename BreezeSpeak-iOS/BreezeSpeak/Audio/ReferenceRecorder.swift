//
//  ReferenceRecorder.swift
//  BreezeSpeak
//
//  克隆用的现场录音：直接录成 24 kHz / 16-bit / 单声道 WAV，
//  与引擎参考音频同规格，免去转码。录满上限自动停。
//

import AVFoundation

@MainActor
final class ReferenceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0

    /// 录完（手动停或到时长上限）回调，参数为 WAV 文件 URL
    var onFinished: ((URL?) -> Void)?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    var formattedElapsed: String {
        String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("breeze_memo_\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: AppConfig.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let created = try AVAudioRecorder(url: url, settings: settings)
            created.record(forDuration: AppConfig.maxReferenceSeconds) // 到 30 秒自动停
            recorder = created
            elapsed = 0
            isRecording = true

            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let recorder = self.recorder, self.isRecording else { return }
                    self.elapsed = recorder.currentTime
                    // AVAudioRecorder 偶发不触发 delegate，这里兜底检查
                    if self.elapsed >= AppConfig.maxReferenceSeconds - 0.05 {
                        self.stop()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            meterTimer = timer
            Haptics.light()
        } catch {
            onFinished?(nil)
        }
    }

    func stop() {
        guard isRecording, let recorder else { return }
        meterTimer?.invalidate()
        meterTimer = nil
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let valid = elapsed >= AppConfig.minReferenceSeconds * 0.8
        onFinished?(valid ? url : nil)
        if !valid {
            elapsed = 0
        }
    }
}
