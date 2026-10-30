//
//  TextSegmenter.swift
//  BreezeSpeak
//
//  Breeze 原生标记解析：
//    |  短停顿      ||  长停顿
//    (slow) 慢速   (fast) 加速   (whisper) 轻声
//    [笑] [叹气] [咳嗽] 等副语言标记（神经引擎原生渲染）
//  长文本按标点 + 字数上限自动分段，交给引擎流式推理。
//

import Foundation

struct ParsedSpeech {
    var segments: [TTSSegment]
    var containsParalinguistic: Bool
    var containsPause: Bool
}

enum TextSegmenter {
    private static let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "…", "：", ":"]
    private static let softBreaks: Set<Character> = ["，", ",", "、", "）", ")", "】", "」"]

    static func parse(_ raw: String, limit: Int = AppConfig.segmentCharLimit) -> ParsedSpeech {
        var segments: [TTSSegment] = []
        var buffer = ""
        var modifier: SpeechModifier = .none
        var hasParalinguistic = false
        var hasPause = false

        let characters = Array(raw)
        var index = 0

        func flush(pause: Double) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(TTSSegment(text: trimmed, pauseAfter: pause, modifier: modifier))
            }
            buffer.removeAll(keepingCapacity: true)
            modifier = .none
        }

        while index < characters.count {
            let character = characters[index]

            if character == "[" {
                if let closing = characters[index...].firstIndex(of: "]") {
                    let token = String(characters[(index + 1)..<closing])
                    if !token.hasPrefix("spk_") {
                        hasParalinguistic = true
                        buffer.append(contentsOf: "[\(token)]")
                    }
                    index = closing + 1
                    continue
                }
            }

            if character == "(" || character == "（" {
                let closingCharacter: Character = character == "(" ? ")" : "）"
                if let closing = characters[index...].firstIndex(of: closingCharacter) {
                    let token = String(characters[(index + 1)..<closing]).lowercased()
                    switch token {
                    case "slow", "慢速": modifier = .slow
                    case "fast", "加速": modifier = .fast
                    case "whisper", "轻声": modifier = .whisper
                    default: break
                    }
                    index = closing + 1
                    continue
                }
            }

            if character == "|" {
                hasPause = true
                var pause = AppConfig.shortPauseSeconds
                if index + 1 < characters.count, characters[index + 1] == "|" {
                    pause = AppConfig.longPauseSeconds
                    index += 1
                }
                flush(pause: pause)
                index += 1
                continue
            }

            if character == "\n" {
                hasPause = true
                flush(pause: AppConfig.shortPauseSeconds * 1.4)
                index += 1
                continue
            }

            buffer.append(character)

            if sentenceEnders.contains(character) {
                flush(pause: 0.14)
            } else if softBreaks.contains(character) && buffer.count >= limit * 6 / 10 {
                flush(pause: 0.10)
            } else if buffer.count >= limit {
                // 无标点的长句：在最近一个可断处（或硬切）断开
                flush(pause: 0.08)
            }
            index += 1
        }

        flush(pause: 0)
        return ParsedSpeech(
            segments: segments,
            containsParalinguistic: hasParalinguistic,
            containsPause: hasPause
        )
    }

    /// 剥离全部原生标记，供系统兜底引擎朗读
    static func plainText(_ raw: String) -> String {
        var output = ""
        var index = 0
        let characters = Array(raw)
        while index < characters.count {
            let character = characters[index]
            if character == "[" || character == "(" || character == "（" {
                let closing: Character? = character == "[" ? "]" : (character == "(" ? ")" : "）")
                if let closing, let end = characters[index...].firstIndex(of: closing) {
                    index = end + 1
                    continue
                }
            }
            if character == "|" {
                index += 1
                continue
            }
            output.append(character)
            index += 1
        }
        return output
    }

    static func estimatedSpeechSeconds(_ text: String) -> Double {
        let count = Double(plainText(text).count)
        return max(0.6, count / 4.6)
    }
}
