import AmbientCore
import AppKit
import SwiftUI

struct VoicePane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    @ObservedObject var speech: SpeechController
    @ObservedObject var shortcuts: ShortcutCenter

    @State private var apiKey = ""
    @State private var loadedKey = ""
    @State private var accessGranted = SelectionReader.isTrusted

    private var kind: SpeechEngineKind { prefs.speechEngineKind ?? .mac }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .voice)
            SettingsSection(footer: "In apps that support it, also under the app's menu › Services › Speak with Ambient.") {
                SettingsRow(title: "Shortcut", subtitle: "Select text and press it. Press it again to stop.") {
                    ShortcutRecorder(center: shortcuts)
                }
                SettingsDivider()
                SettingsRow(title: "Accessibility",
                            subtitle: "Lets Ambient read the selection when you press the shortcut, and nothing else.") {
                    if accessGranted {
                        StatusBadge("Allowed", .success)
                    } else {
                        Button("Allow…") { SelectionReader.askForAccess() }.buttonStyle(.pill)
                    }
                }
            }
            SettingsSection(footer: nil) {
                SettingsRow(title: "Voice") {
                    Picker("Voice", selection: Binding(get: { kind }, set: { prefs.speechEngine = $0.rawValue })) {
                        ForEach(SpeechEngineKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                EngineSection(kind: kind, prefs: prefs, voicePack: voicePack, apiKey: $apiKey, loadedKey: $loadedKey)
                    .padding(.vertical, Theme.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if kind == .kokoro, voicePack.status == .installed {
                    SettingsDivider()
                    SettingsRow(title: "Offline model", subtitle: voicePack.downloadSize + " on this Mac.") {
                        Button("Remove") { voicePack.remove() }.buttonStyle(.pill)
                    }
                }
            }
            SettingsSection(footer: nil) {
                SettingsRow(title: "Speed") {
                    Slider(value: $prefs.speechRate, in: 0.5...2, step: 0.1).frame(width: 180)
                }
                SettingsDivider()
                SettingsToggleRow(title: "Read code blocks",
                                  subtitle: "Off: a code block is read as \u{201C}code block, 12 lines\u{201D}.",
                                  isOn: $prefs.speechReadsCode)
                SettingsDivider()
                SettingsRow(title: "Try it") {
                    Button(speech.isActive ? "Stop" : "Preview") {
                        if speech.isActive {
                            speech.stop()
                        } else {
                            EngineSection.saveKey(apiKey, loaded: $loadedKey, prefs: prefs)
                            speech.preview(kind)
                        }
                    }
                    .buttonStyle(.pill)
                    .disabled(!EngineSection.ready(kind, prefs: prefs, voicePack: voicePack, apiKey: apiKey))
                }
            }
        }
        .onAppear {
            EngineSection.loadKey(prefs: prefs, into: $apiKey, loaded: $loadedKey)
            voicePack.refresh()
            accessGranted = SelectionReader.isTrusted
        }
        // Granted in System Settings, then back here.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessGranted = SelectionReader.isTrusted
        }
        // Saved when you try it or leave the pane, not on every keystroke.
        .onDisappear { EngineSection.saveKey(apiKey, loaded: $loadedKey, prefs: prefs) }
    }
}
