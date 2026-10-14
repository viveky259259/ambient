import AmbientCore
import AVFoundation
import SwiftUI

/// The settings for one engine, shared by the first-run chooser and Settings › Voice.
struct EngineSection: View {
    let kind: SpeechEngineKind
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    @Binding var apiKey: String
    /// What the Keychain held when the field was filled; a field still holding it is never saved back.
    @Binding var loadedKey: String

    var body: some View {
        switch kind {
        case .mac: macVoice
        case .kokoro: offline
        case .online: online
        }
    }

    private var macVoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Free and offline. Nothing leaves your Mac.").font(.callout).foregroundStyle(.secondary)
            Picker("Voice", selection: $prefs.macVoice) {
                Text("System voice").tag("")
                ForEach(Self.macVoices, id: \.identifier) { v in
                    Text(Self.label(v)).tag(v.identifier)
                }
            }
            .fixedSize()
            Text("More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kokoro runs on your Mac. Natural, offline, and free after a one-time download.")
                .font(.callout).foregroundStyle(.secondary)
            switch voicePack.status {
            case .unsupported(let reason):
                Text(reason).font(.callout)
            case .unavailable:
                Text("The offline model isn't available in this build of Ambient.").font(.callout)
            case .notInstalled, .failed:
                if case .failed(let message) = voicePack.status {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
                Button("Download (\(voicePack.downloadSize))") { voicePack.install() }
            case .downloading(let fraction):
                HStack {
                    ProgressView(value: fraction).frame(width: 180)
                    Text("\(Int(fraction * 100))%").monospacedDigit()
                    Button("Cancel") { voicePack.cancel() }
                }
            case .installed:
                Picker("Voice", selection: $prefs.kokoroVoice) {
                    ForEach(voicePack.manifest.voices) { Text("\($0.name) (\($0.accent))").tag($0.id) }
                }
                .fixedSize()
            }
        }
    }

    private var online: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Service", selection: $prefs.onlineProvider) {
                ForEach(OnlineProvider.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .onChange(of: prefs.onlineProvider) { _, _ in
                prefs.onlineVoice = prefs.provider.defaultVoice
                prefs.onlineModel = prefs.provider.defaultModel
                Self.loadKey(prefs: prefs, into: $apiKey, loaded: $loadedKey)
            }
            if prefs.provider == .custom {
                TextField("Server URL", text: $prefs.onlineBaseURL, prompt: Text("http://localhost:8880/v1"))
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            SecureField(prefs.provider.needsKey ? "API key" : "API key (optional)", text: $apiKey)
                .textFieldStyle(.roundedBorder).frame(width: 280)
            HStack {
                TextField("Voice", text: $prefs.onlineVoice).textFieldStyle(.roundedBorder).frame(width: 180)
                TextField("Model", text: $prefs.onlineModel).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            Label("The text you select is sent to \(prefs.provider == .custom ? "your server" : prefs.provider.displayName).",
                  systemImage: "network")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private static func label(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: "\(v.name) (Premium)"
        case .enhanced: "\(v.name) (Enhanced)"
        default: v.name
        }
    }

    /// Voices for the user's language, best quality first.
    static var macVoices: [AVSpeechSynthesisVoice] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// Whether this engine can play right now.
    static func ready(_ kind: SpeechEngineKind, prefs: Preferences, voicePack: VoicePackInstaller, apiKey: String) -> Bool {
        switch kind {
        case .mac: true
        case .kokoro: voicePack.status == .installed
        case .online: !prefs.provider.needsKey || !apiKey.isEmpty
        }
    }

    /// Fills the field from the Keychain, off the main thread.
    static func loadKey(prefs: Preferences, into apiKey: Binding<String>, loaded: Binding<String>) {
        KeychainStore.load(for: prefs.provider) { key in
            apiKey.wrappedValue = key
            loaded.wrappedValue = key
        }
    }

    /// Saves the key only if the user changed it, so a Keychain read that failed (and left the field empty) never
    /// deletes the stored key. An emptied field forgets it.
    static func saveKey(_ apiKey: String, loaded: Binding<String>, prefs: Preferences) {
        guard apiKey != loaded.wrappedValue else { return }
        KeychainStore.save(apiKey, for: prefs.provider)
        loaded.wrappedValue = apiKey
    }
}
