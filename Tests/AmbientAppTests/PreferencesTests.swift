@testable import AmbientApp
@testable import AmbientCore
import Foundation
import Testing

@Suite struct PreferencesTests {
    @Test func freshInstallUsesTheRegisteredDefaults() throws {
        let box = try AppSandbox()
        let p = box.preferences()
        #expect(p.islandEnabled && p.islandShowsWorking && p.notificationsEnabled && p.soundsEnabled)
        #expect(p.soundVolume == 0.6)
        #expect(p.dockGlowEnabled && p.dockGlowIntensity == 1.0)
        #expect(p.doneThreshold == 20)
        #expect(p.quietUntil == nil && !p.isQuiet)
        #expect(!p.setupCompleted)
        #expect(!p.wallpaperEnabled && p.wallpaperScene == "daily" && p.wallpaperOnLockScreen)
        #expect(!p.wallpaperLockMessages && !p.wallpaperCalendar && !p.wallpaperShowBoard && p.wallpaperIslandEffect)
        #expect(p.wallpaperLook == "timeOfDay")
        #expect(!p.petEnabled && p.petSpecies == PetSpecies.blob.rawValue && p.petOrigin == nil)
        #expect(p.speechEngine == nil && p.macVoice.isEmpty)
        #expect(p.kokoroVoice == VoicePackManifest.current.defaultVoice)
        #expect(p.onlineProvider == OnlineProvider.openAI.rawValue)
        #expect(p.onlineVoice == OnlineProvider.openAI.defaultVoice && p.onlineModel == OnlineProvider.openAI.defaultModel)
        #expect(p.onlineBaseURL == "http://localhost:8880/v1")
        #expect(p.speechRate == 1.0 && !p.speechReadsCode && !p.speechAccessExplained)
        #expect(p.speechShortcut == nil)
        #expect(!p.taskLLMEnabled && p.taskLLMMCPURL == "http://127.0.0.1:5051/mcp")
        #expect(p.taskLLMModelID == "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit")
        #expect(p.taskLLMModelPath.isEmpty && p.taskLLMPython.isEmpty && !p.taskLLMReadTranscripts)
        #expect(p.taskLLMModelsVolume == "/Volumes/Models")
        #expect(!p.remoteSummaries)
        #expect(p.voiceSyncShortcut == nil && p.voiceSyncDestination == nil && p.voiceSyncCopySeconds == 60)
        #expect(!p.answerPermissions && p.permissionWait == 20)
    }

    @Test func everyKindOfSettingSurvivesARelaunch() throws {
        let box = try AppSandbox()
        let p = box.preferences()
        let quiet = Date(timeIntervalSinceNow: 3_600)
        p.islandEnabled = false
        p.soundVolume = 0.25
        p.doneThreshold = 45
        p.quietUntil = quiet
        p.setupCompleted = true
        p.wallpaperScene = "harbor"
        p.wallpaperLook = "dark"
        p.petSpecies = PetSpecies.cat.rawValue
        p.speechEngine = SpeechEngineKind.online.rawValue
        p.onlineProvider = OnlineProvider.elevenLabs.rawValue
        p.speechRate = 1.5
        p.speechShortcut = "opt+esc"
        p.taskLLMEnabled = true
        p.taskLLMModelPath = "/Volumes/Models/x.gguf"
        p.remoteSummaries = true
        p.voiceSyncDestination = "studio"
        p.voiceSyncCopySeconds = 90

        let q = box.relaunched()
        #expect(!q.islandEnabled)
        #expect(q.soundVolume == 0.25)
        #expect(q.doneThreshold == 45)
        #expect(abs((q.quietUntil ?? .distantPast).timeIntervalSince(quiet)) < 0.001)
        #expect(q.isQuiet)
        #expect(q.setupCompleted)
        #expect(q.wallpaperScene == "harbor" && q.sceneChoice == .fixed(.harbor))
        #expect(q.wallpaperLook == "dark" && q.sceneLook == .dark)
        #expect(q.pet == .cat)
        #expect(q.speechEngineKind == .online)
        #expect(q.provider == .elevenLabs)
        #expect(q.speechRate == 1.5)
        #expect(q.speechShortcut == "opt+esc")
        #expect(q.taskLLMEnabled && q.taskLLMModelPath == "/Volumes/Models/x.gguf")
        #expect(q.remoteSummaries)
        #expect(q.voiceSyncDestination == "studio" && q.voiceSyncCopySeconds == 90)
    }

    @Test func petOriginIsStoredAsAPairAndClearedByNil() throws {
        let box = try AppSandbox()
        let p = box.preferences()
        p.petOrigin = CGPoint(x: 120.5, y: 64)
        #expect(box.defaults.array(forKey: "petOrigin") as? [Double] == [120.5, 64])
        #expect(box.relaunched().petOrigin == CGPoint(x: 120.5, y: 64))
        p.petOrigin = nil
        #expect(box.defaults.object(forKey: "petOrigin") == nil)
        #expect(box.relaunched().petOrigin == nil)
    }

    @Test func malformedPetOriginIsIgnored() throws {
        let box = try AppSandbox()
        box.defaults.set([1.0], forKey: "petOrigin")
        #expect(box.preferences().petOrigin == nil)
    }

    @Test func unknownStoredValuesFallBackToSafeChoices() throws {
        let box = try AppSandbox()
        let p = box.preferences()
        p.wallpaperScene = "moon"
        p.wallpaperLook = "sepia"
        p.petSpecies = "dragon"
        p.speechEngine = "robot"
        p.onlineProvider = "nope"
        #expect(p.sceneChoice == .daily)
        #expect(p.sceneLook == .timeOfDay)
        #expect(p.pet == .blob)
        #expect(p.speechEngineKind == nil)
        #expect(p.provider == .openAI)
    }

    @Test func pastQuietTimeIsNotQuiet() throws {
        let p = try AppSandbox().preferences()
        p.quietUntil = Date(timeIntervalSinceNow: -5)
        #expect(!p.isQuiet)
        #expect(p.alertSettings.quiet == false)
    }

    @Test func alertSettingsMirrorThePreferences() throws {
        let p = try AppSandbox().preferences()
        p.notificationsEnabled = false
        p.soundsEnabled = true
        p.doneThreshold = 7
        p.quietUntil = Date(timeIntervalSinceNow: 60)
        #expect(p.alertSettings == AlertPolicy.Settings(notifications: false, sounds: true, doneThreshold: 7, quiet: true))
    }

    @Test func taskLLMConfigIsComposedFromTheBoardSettings() throws {
        let p = try AppSandbox().preferences()
        p.taskLLMEnabled = true
        p.taskLLMMCPURL = "http://localhost:9000/mcp"
        p.taskLLMModelID = "ollama:qwen"
        p.taskLLMModelPath = "/m/q.gguf"
        p.taskLLMPython = "/usr/bin/python3"
        p.taskLLMReadTranscripts = true
        p.taskLLMModelsVolume = "/Volumes/X"
        let c = p.taskLLMConfig
        #expect(c == TaskLLMConfig(enabled: true, mcpURL: "http://localhost:9000/mcp", modelID: "ollama:qwen",
                                   modelPath: "/m/q.gguf", pythonPath: "/usr/bin/python3", readTranscripts: true,
                                   modelsVolumePath: "/Volumes/X"))
    }

    @Test func permissionSettingsLiveInTheAmbientHomeNotUserDefaults() throws {
        let box = try AppSandbox()
        let p = box.preferences()
        #expect(!FileManager.default.fileExists(atPath: box.paths.permissionSettings.path))
        p.answerPermissions = true
        p.permissionWait = 30
        #expect(p.permissionSettings == PermissionSettings(enabled: true, wait: 30))
        #expect(PermissionSettings.load(box.paths) == PermissionSettings(enabled: true, wait: 30))
        #expect(box.defaults.object(forKey: "answerPermissions") == nil)
        let q = box.relaunched()
        #expect(q.answerPermissions && q.permissionWait == 30)
    }

    @Test func handEditedPermissionWaitSnapsToAnOfferedOne() throws {
        let box = try AppSandbox()
        try box.paths.ensureHome()
        try Data(#"{"enabled":true,"wait":25}"#.utf8).write(to: box.paths.permissionSettings)
        let p = box.preferences()
        #expect(p.answerPermissions)
        #expect(PermissionSettings.waits.contains(p.permissionWait))
    }
}
