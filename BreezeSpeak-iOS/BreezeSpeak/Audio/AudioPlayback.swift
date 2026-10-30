//
//  AudioPlayback.swift
//  BreezeSpeak
//
//  本地播放（AVAudioEngine + 变速单元）与 AirPlay 路由。
//  音频全部来自沙盒，不经过任何网络。
//

import Foundation
import AVFoundation
import AVKit
import SwiftUI

enum AudioSessionController {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true, options: [])
        } catch {
            // 播放失败不阻塞主流程，AVAudioEngine 会给出具体错误
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    static var currentRouteName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "iPad 扬声器"
    }
}

@MainActor
final class AudioPlayerController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var peaks: [Float] = []
    @Published var playbackRate: Double = 1.0
    @Published private(set) var lastError: String?

    var onPlaybackEnded: (() -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var buffer: AVAudioPCMBuffer?
    private var timer: Timer?
    private var isConfigured = false
    private var playbackStartOffset: Double = 0

    init() {
        engine.attach(player)
        engine.attach(timePitch)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    // MARK: - 载入

    func load(samples: [Float], sampleRate: Double) {
        stop()
        guard !samples.isEmpty else {
            buffer = nil
            duration = 0
            peaks = []
            return
        }

        let sanitized = sampleRate == AppConfig.sampleRate
            ? samples
            : AudioMath.resample(samples, from: sampleRate, to: AppConfig.sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: AppConfig.sampleRate, channels: 1)
        guard let format,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sanitized.count)) else {
            lastError = "无法创建播放缓冲"
            return
        }
        pcm.frameLength = AVAudioFrameCount(sanitized.count)
        if let channel = pcm.floatChannelData?[0] {
            for index in 0..<sanitized.count {
                channel[index] = max(-1, min(1, sanitized[index]))
            }
        }

        buffer = pcm
        duration = Double(pcm.frameLength) / AppConfig.sampleRate
        currentTime = 0
        peaks = AudioAnalysis.peaks(from: sanitized, count: 120)

        connectIfNeeded(format: format)
    }

    func loadFile(at url: URL) {
        do {
            let result = try WAVFile.read(url: url)
            load(samples: result.samples, sampleRate: result.sampleRate)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func connectIfNeeded(format: AVAudioFormat) {
        guard !isConfigured else { return }
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        timePitch.pitch = 0
        timePitch.rate = 1
        engine.prepare()
        isConfigured = true
    }

    // MARK: - 播放控制

    func play() {
        guard let buffer else { return }
        AudioSessionController.activate()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
            return
        }
        timePitch.rate = Float(playbackRate)

        if currentTime >= duration - 0.02 {
            currentTime = 0
        }

        // 从当前位置继续：整体重排一次缓冲（音频短，代价可忽略）
        player.stop()
        let offset = AVAudioFramePosition(currentTime * AppConfig.sampleRate)
        guard offset < AVAudioFramePosition(buffer.frameLength) else { return }
        let remaining = buffer.frameLength - AVAudioFrameCount(offset)
        guard let segment = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remaining) else { return }
        segment.frameLength = remaining
        if let source = buffer.floatChannelData?[0], let target = segment.floatChannelData?[0] {
            for index in 0..<Int(remaining) {
                target[index] = source[index + Int(offset)]
            }
        }
        player.scheduleBuffer(segment, at: nil, options: []) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying {
                    self.isPlaying = false
                    self.currentTime = self.duration
                    self.stopTimer()
                    self.onPlaybackEnded?()
                }
            }
        }
        playbackStartOffset = currentTime
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: Double) {
        currentTime = min(max(0, time), duration)
        if isPlaying {
            isPlaying = false
            player.stop()
            play()
        }
    }

    // MARK: - 计时

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                guard let nodeTime = self.player.lastRenderTime,
                      let playerTime = self.player.playerTime(forNodeTime: nodeTime) else { return }
                let played = Double(playerTime.sampleTime) / AppConfig.sampleRate
                self.currentTime = min(self.duration, self.playbackStartOffset + played)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - AirPlay 路由

struct AirPlayRoutePicker: UIViewRepresentable {
    var tint: Color = Palette.ink

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(Palette.accent)
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor(tint)
    }
}

/// 玻璃底 + 系统原生 AirPlay 按钮（点击直接调起系统路由面板）
struct AirPlayButton: View {
    var size: CGFloat = 42

    var body: some View {
        AirPlayRoutePicker(tint: Palette.ink)
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Palette.selectionFill.opacity(0.5))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.7) }
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            }
    }
}
