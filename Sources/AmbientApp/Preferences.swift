import AmbientCore
import Combine
import Foundation

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    @Published var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: "islandEnabled") } }
    @Published var islandShowsWorking: Bool { didSet { defaults.set(islandShowsWorking, forKey: "islandShowsWorking") } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: "soundVolume") } }
    @Published var dockGlowEnabled: Bool { didSet { defaults.set(dockGlowEnabled, forKey: "dockGlowEnabled") } }
    @Published var dockGlowIntensity: Double { didSet { defaults.set(dockGlowIntensity, forKey: "dockGlowIntensity") } }
    /// Seconds a turn must run before finishing it notifies.
    @Published var doneThreshold: Double { didSet { defaults.set(doneThreshold, forKey: "doneThreshold") } }
    @Published var quietUntil: Date? { didSet { defaults.set(quietUntil, forKey: "quietUntil") } }
    @Published var setupCompleted: Bool { didSet { defaults.set(setupCompleted, forKey: "setupCompleted") } }
    @Published var wallpaperEnabled: Bool { didSet { defaults.set(wallpaperEnabled, forKey: "wallpaperEnabled") } }
    /// "sky", "harbor", "garden" or "daily".
    @Published var wallpaperScene: String { didSet { defaults.set(wallpaperScene, forKey: "wallpaperScene") } }
    @Published var wallpaperOnLockScreen: Bool { didSet { defaults.set(wallpaperOnLockScreen, forKey: "wallpaperOnLockScreen") } }
    @Published var wallpaperLockMessages: Bool { didSet { defaults.set(wallpaperLockMessages, forKey: "wallpaperLockMessages") } }
    @Published var wallpaperCalendar: Bool { didSet { defaults.set(wallpaperCalendar, forKey: "wallpaperCalendar") } }
    /// Soft task cues on the living wallpaper (off by default — like calendar / lock messages).
    @Published var wallpaperShowBoard: Bool { didSet { defaults.set(wallpaperShowBoard, forKey: "wallpaperShowBoard") } }
    @Published var wallpaperIslandEffect: Bool { didSet { defaults.set(wallpaperIslandEffect, forKey: "wallpaperIslandEffect") } }
    @Published var wallpaperLook: String { didSet { defaults.set(wallpaperLook, forKey: "wallpaperLook") } }
    @Published var petEnabled: Bool { didSet { defaults.set(petEnabled, forKey: "petEnabled") } }
    /// A `PetSpecies` raw value.
    @Published var petSpecies: String { didSet { defaults.set(petSpecies, forKey: "petSpecies") } }
    /// Where the pet stands, in global screen coordinates; nil for the default corner.
    @Published var petOrigin: CGPoint? {
        didSet {
            if let petOrigin {
                defaults.set([petOrigin.x, petOrigin.y], forKey: "petOrigin")
            } else {
                defaults.removeObject(forKey: "petOrigin")
            }
        }
    }

    /// A `SpeechEngineKind` raw value; nil until the voice chooser has run.
    @Published var speechEngine: String? { didSet { defaults.set(speechEngine, forKey: "speechEngine") } }
    /// An `AVSpeechSynthesisVoice` identifier; empty for the system's default voice.
    @Published var macVoice: String { didSet { defaults.set(macVoice, forKey: "macVoice") } }
    @Published var kokoroVoice: String { didSet { defaults.set(kokoroVoice, forKey: "kokoroVoice") } }
    /// An `OnlineProvider` raw value.
    @Published var onlineProvider: String { didSet { defaults.set(onlineProvider, forKey: "onlineProvider") } }
    @Published var onlineVoice: String { didSet { defaults.set(onlineVoice, forKey: "onlineVoice") } }
    @Published var onlineModel: String { didSet { defaults.set(onlineModel, forKey: "onlineModel") } }
    /// For `OnlineProvider.custom`: an OpenAI-compatible base URL such as http://localhost:8880/v1.
    @Published var onlineBaseURL: String { didSet { defaults.set(onlineBaseURL, forKey: "onlineBaseURL") } }
    /// 1 is normal speed; 0.5 to 2.
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: "speechRate") } }
    @Published var speechReadsCode: Bool { didSet { defaults.set(speechReadsCode, forKey: "speechReadsCode") } }
    /// The Accessibility explanation has been shown once (hotkey route only).
    @Published var speechAccessExplained: Bool { didSet { defaults.set(speechAccessExplained, forKey: "speechAccessExplained") } }
    /// A `Shortcut.stored` value; nil for the default (⌥⎋).
    @Published var speechShortcut: String? { didSet { defaults.set(speechShortcut, forKey: "speechShortcut") } }
    /// The island has shown its one-time read-aloud hint, or the shortcut has been used, so no hint is needed.
    @Published var speechHintShown: Bool { didSet { defaults.set(speechHintShown, forKey: "speechHintShown") } }

    // MARK: - Task board local LLM (local-agent MCP)

    @Published var taskLLMEnabled: Bool { didSet { defaults.set(taskLLMEnabled, forKey: "taskLLMEnabled") } }
    /// Streamable HTTP MCP URL for local-agent (default LaunchAgent on this Mac).
    @Published var taskLLMMCPURL: String { didSet { defaults.set(taskLLMMCPURL, forKey: "taskLLMMCPURL") } }
    @Published var taskLLMModelID: String { didSet { defaults.set(taskLLMModelID, forKey: "taskLLMModelID") } }
    /// A model folder or .gguf file on this Mac; when set it wins over the model id.
    @Published var taskLLMModelPath: String { didSet { defaults.set(taskLLMModelPath, forKey: "taskLLMModelPath") } }
    /// Python with mlx-lm / mlx-vlm for running a model path directly; empty to find one.
    @Published var taskLLMPython: String { didSet { defaults.set(taskLLMPython, forKey: "taskLLMPython") } }
    /// Opt-in: read local Claude/Codex transcript stores for richer summaries.
    @Published var taskLLMReadTranscripts: Bool { didSet { defaults.set(taskLLMReadTranscripts, forKey: "taskLLMReadTranscripts") } }
    @Published var taskLLMModelsVolume: String { didSet { defaults.set(taskLLMModelsVolume, forKey: "taskLLMModelsVolume") } }

    // MARK: - Remote machines

    /// Opt-in: the local LLM may summarize remote sessions. Off, their text never reaches it.
    @Published var remoteSummaries: Bool { didSet { defaults.set(remoteSummaries, forKey: "remoteSummaries") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "islandEnabled": true,
            "islandShowsWorking": true,
            "notificationsEnabled": true,
            "soundsEnabled": true,
            "soundVolume": 0.6,
            "dockGlowEnabled": true,
            "dockGlowIntensity": 1.0,
            "doneThreshold": 20.0,
            "setupCompleted": false,
            "wallpaperEnabled": false,
            "wallpaperScene": "daily",
            "wallpaperOnLockScreen": true,
            "wallpaperLockMessages": false,
            "wallpaperCalendar": false,
            "wallpaperShowBoard": false,
            "wallpaperIslandEffect": true,
            "wallpaperLook": "timeOfDay",
            "petEnabled": false,
            "petSpecies": PetSpecies.blob.rawValue,
            "macVoice": "",
            "kokoroVoice": VoicePackManifest.current.defaultVoice,
            "onlineProvider": OnlineProvider.openAI.rawValue,
            "onlineVoice": OnlineProvider.openAI.defaultVoice,
            "onlineModel": OnlineProvider.openAI.defaultModel,
            "onlineBaseURL": "http://localhost:8880/v1",
            "speechRate": 1.0,
            "speechReadsCode": false,
            "speechAccessExplained": false,
            "taskLLMEnabled": false,
            "taskLLMMCPURL": "http://127.0.0.1:5051/mcp",
            "taskLLMModelID": "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            "taskLLMModelPath": "",
            "taskLLMPython": "",
            "taskLLMReadTranscripts": false,
            "taskLLMModelsVolume": "/Volumes/Models",
            "remoteSummaries": false,
        ])
        islandEnabled = defaults.bool(forKey: "islandEnabled")
        islandShowsWorking = defaults.bool(forKey: "islandShowsWorking")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        soundsEnabled = defaults.bool(forKey: "soundsEnabled")
        soundVolume = defaults.double(forKey: "soundVolume")
        dockGlowEnabled = defaults.bool(forKey: "dockGlowEnabled")
        dockGlowIntensity = defaults.double(forKey: "dockGlowIntensity")
        doneThreshold = defaults.double(forKey: "doneThreshold")
        quietUntil = defaults.object(forKey: "quietUntil") as? Date
        setupCompleted = defaults.bool(forKey: "setupCompleted")
        wallpaperEnabled = defaults.bool(forKey: "wallpaperEnabled")
        wallpaperScene = defaults.string(forKey: "wallpaperScene") ?? "daily"
        wallpaperOnLockScreen = defaults.bool(forKey: "wallpaperOnLockScreen")
        wallpaperLockMessages = defaults.bool(forKey: "wallpaperLockMessages")
        wallpaperCalendar = defaults.bool(forKey: "wallpaperCalendar")
        wallpaperShowBoard = defaults.bool(forKey: "wallpaperShowBoard")
        wallpaperIslandEffect = defaults.bool(forKey: "wallpaperIslandEffect")
        wallpaperLook = defaults.string(forKey: "wallpaperLook") ?? "timeOfDay"
        petEnabled = defaults.bool(forKey: "petEnabled")
        petSpecies = defaults.string(forKey: "petSpecies") ?? PetSpecies.blob.rawValue
        if let xy = defaults.array(forKey: "petOrigin") as? [Double], xy.count == 2 {
            petOrigin = CGPoint(x: xy[0], y: xy[1])
        } else {
            petOrigin = nil
        }
        speechEngine = defaults.string(forKey: "speechEngine")
        macVoice = defaults.string(forKey: "macVoice") ?? ""
        kokoroVoice = defaults.string(forKey: "kokoroVoice") ?? VoicePackManifest.current.defaultVoice
        onlineProvider = defaults.string(forKey: "onlineProvider") ?? OnlineProvider.openAI.rawValue
        onlineVoice = defaults.string(forKey: "onlineVoice") ?? OnlineProvider.openAI.defaultVoice
        onlineModel = defaults.string(forKey: "onlineModel") ?? OnlineProvider.openAI.defaultModel
        onlineBaseURL = defaults.string(forKey: "onlineBaseURL") ?? "http://localhost:8880/v1"
        speechRate = defaults.double(forKey: "speechRate")
        speechReadsCode = defaults.bool(forKey: "speechReadsCode")
        speechAccessExplained = defaults.bool(forKey: "speechAccessExplained")
        speechShortcut = defaults.string(forKey: "speechShortcut")
        speechHintShown = defaults.bool(forKey: "speechHintShown")
        taskLLMEnabled = defaults.bool(forKey: "taskLLMEnabled")
        taskLLMMCPURL = defaults.string(forKey: "taskLLMMCPURL") ?? "http://127.0.0.1:5051/mcp"
        taskLLMModelID = defaults.string(forKey: "taskLLMModelID")
            ?? "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        taskLLMModelPath = defaults.string(forKey: "taskLLMModelPath") ?? ""
        taskLLMPython = defaults.string(forKey: "taskLLMPython") ?? ""
        taskLLMReadTranscripts = defaults.bool(forKey: "taskLLMReadTranscripts")
        remoteSummaries = defaults.bool(forKey: "remoteSummaries")
        taskLLMModelsVolume = defaults.string(forKey: "taskLLMModelsVolume") ?? "/Volumes/Models"
    }

    var taskLLMConfig: TaskLLMConfig {
        TaskLLMConfig(enabled: taskLLMEnabled, mcpURL: taskLLMMCPURL, modelID: taskLLMModelID,
                      modelPath: taskLLMModelPath, pythonPath: taskLLMPython,
                      readTranscripts: taskLLMReadTranscripts, modelsVolumePath: taskLLMModelsVolume)
    }

    var isQuiet: Bool {
        guard let quietUntil else { return false }
        return quietUntil > Date()
    }

    var alertSettings: AlertPolicy.Settings {
        AlertPolicy.Settings(notifications: notificationsEnabled, sounds: soundsEnabled,
                             doneThreshold: doneThreshold, quiet: isQuiet)
    }

    var sceneChoice: SceneChoice { SceneChoice(rawValue: wallpaperScene) ?? .daily }
    var sceneLook: SceneLook { SceneLook(rawValue: wallpaperLook) ?? .timeOfDay }
    var pet: PetSpecies { PetSpecies(stored: petSpecies) }
    var speechEngineKind: SpeechEngineKind? { speechEngine.flatMap(SpeechEngineKind.init(rawValue:)) }
    var provider: OnlineProvider { OnlineProvider(rawValue: onlineProvider) ?? .openAI }
}
