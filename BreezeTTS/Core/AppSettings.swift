import Combine
import Foundation

/// Persisted preferences. Everything the user can tune lives here so the UI
/// never owns state directly.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var strategy: ModelStrategy { didSet { defaults.set(strategy.rawValue, forKey: Keys.strategy) } }
    /// nil 表示跟随策略推荐
    @Published var overrideTierID: String? { didSet { defaults.set(overrideTierID, forKey: Keys.override) } }
    @Published var customModelPath: String? { didSet { defaults.set(customModelPath, forKey: Keys.customPath) } }
    @Published var useGPU: Bool { didSet { defaults.set(useGPU, forKey: Keys.useGPU) } }

    @Published var instruction: String { didSet { defaults.set(instruction, forKey: Keys.instruction) } }
    /// The hand-written instruction that a preset replaced, so the menu can offer
    /// it back instead of silently losing the user's wording.
    @Published var instructionBackup: String? { didSet { defaults.set(instructionBackup, forKey: Keys.instructionBackup) } }
    @Published var seed: Int { didSet { defaults.set(seed, forKey: Keys.seed) } }
    @Published var randomSeed: Bool { didSet { defaults.set(randomSeed, forKey: Keys.randomSeed) } }
    @Published var temperature: Double { didSet { defaults.set(temperature, forKey: Keys.temperature) } }
    @Published var topK: Int { didSet { defaults.set(topK, forKey: Keys.topK) } }
    @Published var topP: Double { didSet { defaults.set(topP, forKey: Keys.topP) } }
    @Published var repetitionPenalty: Double { didSet { defaults.set(repetitionPenalty, forKey: Keys.repPenalty) } }
    @Published var cfgScale: Double { didSet { defaults.set(cfgScale, forKey: Keys.cfgScale) } }
    @Published var maxNewTokens: Int { didSet { defaults.set(maxNewTokens, forKey: Keys.maxFrames) } }
    @Published var splitChars: Int { didSet { defaults.set(splitChars, forKey: Keys.splitChars) } }

    /// 边生成边播放。关闭（默认）= 整段一次解码，更快，结束时自动播放；
    /// 打开 = 流式，边合成边出声，但端到端更慢。
    @Published var streamPlayback: Bool { didSet { defaults.set(streamPlayback, forKey: Keys.streamPlayback) } }
    /// Set once the guided first-run setup has been finished.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: Keys.onboarded) } }

    /// macOS 26+ 的液态玻璃。关掉后统一用毛玻璃材质，12–15 上本来就只有毛玻璃。
    @Published var useLiquidGlass: Bool {
        didSet {
            defaults.set(useLiquidGlass, forKey: Keys.useLiquidGlass)
            Appearance.liquidGlassEnabled = useLiquidGlass
        }
    }
    /// 强调色跟随系统「外观 → 强调色」。关掉则回到黑白单色。
    @Published var followSystemAccent: Bool {
        didSet {
            defaults.set(followSystemAccent, forKey: Keys.followSystemAccent)
            Appearance.followSystemAccent = followSystemAccent
        }
    }
    /// 生成音频的保存位置；nil 表示用默认的 App 数据目录。
    @Published var exportDirectory: String? { didSet { defaults.set(exportDirectory, forKey: Keys.exportDirectory) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawStrategy = defaults.string(forKey: Keys.strategy) ?? ModelStrategy.auto.rawValue
        self.strategy = ModelStrategy(rawValue: rawStrategy) ?? .auto
        self.overrideTierID = defaults.string(forKey: Keys.override)
        self.customModelPath = defaults.string(forKey: Keys.customPath)
        self.useGPU = defaults.object(forKey: Keys.useGPU) as? Bool ?? true

        self.instruction = defaults.string(forKey: Keys.instruction) ?? AppSettings.defaultInstruction
        self.instructionBackup = defaults.string(forKey: Keys.instructionBackup)
        self.seed = defaults.object(forKey: Keys.seed) as? Int ?? 42
        self.randomSeed = defaults.object(forKey: Keys.randomSeed) as? Bool ?? false
        self.temperature = defaults.object(forKey: Keys.temperature) as? Double ?? 0.0
        self.topK = defaults.object(forKey: Keys.topK) as? Int ?? 0
        self.topP = defaults.object(forKey: Keys.topP) as? Double ?? 0.0
        self.repetitionPenalty = defaults.object(forKey: Keys.repPenalty) as? Double ?? 0.0
        self.cfgScale = defaults.object(forKey: Keys.cfgScale) as? Double ?? 1.0
        self.maxNewTokens = defaults.object(forKey: Keys.maxFrames) as? Int ?? 0
        self.splitChars = defaults.object(forKey: Keys.splitChars) as? Int ?? 0
        self.streamPlayback = defaults.object(forKey: Keys.streamPlayback) as? Bool ?? false
        self.onboarded = defaults.object(forKey: Keys.onboarded) as? Bool ?? false
        let glass = defaults.object(forKey: Keys.useLiquidGlass) as? Bool ?? true
        let accent = defaults.object(forKey: Keys.followSystemAccent) as? Bool ?? true
        self.useLiquidGlass = glass
        self.followSystemAccent = accent
        self.exportDirectory = defaults.string(forKey: Keys.exportDirectory)
        Appearance.liquidGlassEnabled = glass
        Appearance.followSystemAccent = accent
    }

    /// 生成音频落到哪个文件夹。
    var exportFolder: URL {
        guard let path = exportDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return Paths.exports }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    var selection: ModelSelection {
        ModelSelection(strategy: strategy, memoryGB: DeviceInfo.memoryGB)
    }

    /// 出厂默认音色：成年女性、中文普通话、自然口语（不带播音腔）。
    static let defaultInstruction = "一位成年女性，中文普通话，声音温柔自然，语速适中，吐字清晰，像面对面聊天一样放松，不要播音腔。"

    /// 推荐档（未考虑覆盖）
    var recommendedSpec: ModelSpec { selection.recommendedSpec }

    /// 最终生效
    var resolvedSpec: ModelSpec {
        ModelCatalog.spec(id: selection.resolvedID(overrideID: overrideTierID)) ?? recommendedSpec
    }

    func genParams() -> GenParams {
        GenParams(
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            seed: randomSeed ? Int.random(in: 0...Int(Int32.max)) : seed,
            cfgScale: Float(cfgScale),
            maxNewTokens: maxNewTokens,
            splitChars: splitChars,
            temperature: Float(temperature),
            topK: topK,
            topP: Float(topP),
            repetitionPenalty: Float(repetitionPenalty)
        )
    }

    private enum Keys {
        static let strategy = "model.strategy"
        static let override = "model.override"
        static let customPath = "model.customPath"
        static let useGPU = "engine.useGPU"
        static let instruction = "gen.instruction"
        static let instructionBackup = "gen.instruction.backup"
        static let seed = "gen.seed"
        static let randomSeed = "gen.randomSeed"
        static let temperature = "gen.temperature"
        static let topK = "gen.topK"
        static let topP = "gen.topP"
        static let repPenalty = "gen.repPenalty"
        static let cfgScale = "gen.cfgScale"
        static let maxFrames = "gen.maxNewTokens"
        static let splitChars = "gen.splitChars"
        static let streamPlayback = "playback.streamWhileGenerating"
        static let onboarded = "app.onboarded"
        static let useLiquidGlass = "appearance.liquidGlass"
        static let followSystemAccent = "appearance.systemAccent"
        static let exportDirectory = "export.directory"
    }
}
