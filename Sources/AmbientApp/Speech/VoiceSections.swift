import AmbientCore
import AVFoundation
import SwiftUI

/// The settings for one engine, shared by the first-run chooser and Settings › Voice & Sound.
struct EngineSection: View {
    let kind: SpeechEngineKind
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    @Binding var apiKey: String
    /// What the Keychain held when the field was filled; a field still holding it is never saved back.
    @Binding var loadedKey: String
    /// Settings shows the engine as labelled rows on its card; the first-run chooser, compactly.
    var asRows = false

    var body: some View {
        if asRows {
            rows
        } else {
            switch kind {
            case .mac: macVoice
            case .kokoro: offline
            case .online: online
            }
        }
    }

    /// What the engine is, in a line: the subtitle of Settings' "Read with".
    static func summary(_ kind: SpeechEngineKind) -> String {
        switch kind {
        case .mac: "Free and offline. Nothing leaves your Mac."
        case .kokoro: "Kokoro runs on your Mac. Natural, offline, and free after a one-time download."
        case .online: "A service online reads the text you select, with your own key."
        }
    }

    // MARK: - As rows, in Settings

    @ViewBuilder private var rows: some View {
        switch kind {
        case .mac:
            SettingsRow(title: "Voice",
                        subtitle: "More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.") {
                macPicker.labelsHidden()
            }
        case .kokoro:
            offlineRow
        case .online:
            SettingsRow(title: "Service",
                        subtitle: "The text you select is sent to \(prefs.provider == .custom ? "your server" : prefs.provider.displayName).") {
                servicePicker.labelsHidden()
            }
            if prefs.provider == .custom {
                SettingsDivider()
                SettingsRow(title: "Server") {
                    TextField("Server", text: $prefs.onlineBaseURL, prompt: Text("http://localhost:8880/v1"))
                        .textFieldStyle(.roundedBorder).labelsHidden().frame(width: 220)
                }
            }
            SettingsDivider()
            SettingsRow(title: "API key", subtitle: prefs.provider.needsKey ? nil : "Optional.") {
                SecureField("API key", text: $apiKey).textFieldStyle(.roundedBorder).labelsHidden().frame(width: 220)
            }
            SettingsDivider()
            SettingsRow(title: "Voice") {
                TextField("Voice", text: $prefs.onlineVoice).textFieldStyle(.roundedBorder).labelsHidden().frame(width: 160)
            }
            SettingsDivider()
            SettingsRow(title: "Model") {
                TextField("Model", text: $prefs.onlineModel).textFieldStyle(.roundedBorder).labelsHidden().frame(width: 160)
            }
        }
    }

    @ViewBuilder private var offlineRow: some View {
        switch voicePack.status {
        case .unsupported(let reason):
            SettingsRow(title: "Offline model", subtitle: reason) { EmptyView() }
        case .unavailable:
            SettingsRow(title: "Offline model", subtitle: "This copy of Ambient doesn't come with it.") { EmptyView() }
        case .notInstalled, .failed:
            let failure: String? = if case .failed(let message) = voicePack.status { message } else { nil }
            SettingsRow(title: "Offline model", subtitle: failure ?? "One download of \(voicePack.downloadSize), then it runs on this Mac.",
                        subtitleStatus: failure == nil ? .neutral : .error) {
                Button("Download") { voicePack.install() }.buttonStyle(.pillProminent)
            }
        case .downloading(let fraction):
            SettingsRow(title: "Offline model", subtitle: "Downloading… \(Int(fraction * 100))%") {
                HStack(spacing: Theme.Space.xs) {
                    ProgressView(value: fraction).frame(width: 120)
                    Button("Cancel") { voicePack.cancel() }.buttonStyle(.pill)
                }
            }
        case .installed:
            SettingsRow(title: "Voice") { kokoroPicker.labelsHidden() }
        }
    }

    private var macPicker: some View {
        Picker("Voice", selection: $prefs.macVoice) {
            Text("System voice").tag("")
            ForEach(Self.macVoices, id: \.identifier) { v in
                Text(Self.label(v)).tag(v.identifier)
            }
        }
        .fixedSize()
    }

    private var kokoroPicker: some View {
        Picker("Voice", selection: $prefs.kokoroVoice) {
            ForEach(voicePack.manifest.voices) { Text("\($0.name) (\($0.accent))").tag($0.id) }
        }
        .fixedSize()
    }

    private var servicePicker: some View {
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
    }

    // MARK: - Compact, in the first-run chooser

    private var macVoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.summary(.mac)).font(.callout).foregroundStyle(.secondary)
            macPicker
            Text("More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.summary(.kokoro)).font(.callout).foregroundStyle(.secondary)
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
                kokoroPicker
            }
        }
    }

    private var online: some View {
        VStack(alignment: .leading, spacing: 6) {
            servicePicker
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
