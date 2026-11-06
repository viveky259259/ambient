import AmbientCore
import AppKit
import SwiftUI

/// Sending voices to your other Macs, receiving theirs, and every voice kept on this one.
struct VoiceSyncPane: View {
    @ObservedObject var voice: VoiceSyncController
    @ObservedObject var prefs: Preferences
    @ObservedObject var shortcuts: ShortcutCenter
    @State private var microphone = VoiceSyncController.microphoneAllowed
    @State private var speech = VoiceSyncController.speechAllowed
    /// Looked up on refresh, not in `body`, which runs many times a second while a voice is recorded.
    @State private var canTranscribe = VoiceRecorder.recognizer() != nil
    @State private var confirmingDeleteAll = false

    private static let copyChoices = [(30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes")]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .voiceSync)
            SettingsSection(header: "Send",
                            footer: "Voices stream to the chosen Mac as you speak, over the same ssh link Remote uses. The transcript is made on this Mac; nothing goes to Apple or anyone else.") {
                SettingsRow(title: "Shortcut", subtitle: "Press to start recording, and again to send.") {
                    ShortcutRecorder(center: shortcuts, name: "Voice shortcut")
                }
                SettingsDivider()
                SettingsRow(title: "Send to", subtitle: destinationNote) {
                    if voice.destinations.isEmpty {
                        StatusBadge("No Mac yet", .neutral)
                    } else {
                        Picker("Send to", selection: Binding(get: { voice.destination?.id ?? "" }, set: { id in
                            if let d = voice.destinations.first(where: { $0.id == id }) { voice.choose(d) }
                        })) {
                            ForEach(voice.destinations) { d in
                                Text(verbatim: d.isOnline() ? d.label : "\(d.label) (away)").tag(d.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Microphone", subtitle: "Only while you're recording a voice.") {
                    permission(microphone) {
                        VoiceSyncController.askForMicrophone { microphone = $0 }
                    } settings: {
                        Self.openPrivacy("Privacy_Microphone")
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Transcription",
                            subtitle: !canTranscribe
                                ? "Your language can't be transcribed on this Mac, so voices go as audio only."
                                : "On this Mac only. Without it, voices go as audio only.") {
                    if !canTranscribe {
                        StatusBadge("Unavailable", .neutral)
                    } else {
                        permission(speech) {
                            VoiceSyncController.askForSpeech { speech = $0 }
                        } settings: {
                            Self.openPrivacy("Privacy_SpeechRecognition")
                        }
                    }
                }
            }
            SettingsSection(header: "Receive",
                            footer: "To get voices from another Mac, pair it in Remote with `ambient remote add`. That Mac needs Remote Login on, in System Settings › General › Sharing. Pairing goes one way: to send back, pair this Mac from that one.") {
                SettingsRow(title: "This Mac's name", subtitle: "How your other Macs list it.") {
                    Text(verbatim: voice.hub.label).font(Theme.Fonts.row).foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(title: "Show Copy for", subtitle: "How long a voice that arrives stays under the notch.") {
                    Picker("Show Copy for", selection: $prefs.voiceSyncCopySeconds) {
                        ForEach(Self.copyChoices, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsSection(header: "History", footer: voice.voices.isEmpty ? nil : "Kept on this Mac until you delete them.") {
                if voice.voices.isEmpty {
                    Text("No voices yet.")
                        .font(Theme.Fonts.row)
                        .foregroundStyle(.secondary)
                        .settingsRowPadding()
                }
                ForEach(Array(voice.voices.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { SettingsDivider() }
                    VoiceRow(record: record, voice: voice, playing: voice.playing == record.id)
                }
                if !voice.voices.isEmpty {
                    SettingsDivider()
                    HStack {
                        Spacer()
                        Button("Delete All…") { confirmingDeleteAll = true }.buttonStyle(.pill)
                    }
                    .settingsRowPadding()
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .confirmationDialog("Delete every voice on this Mac?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { voice.deleteAll() }
        } message: {
            Text("Their audio and transcripts go from this Mac. Your other Macs keep their own copies.")
        }
    }

    private var destinationNote: String {
        guard let d = voice.destination else { return "Macs that follow this one show up here." }
        return d.isOnline() ? "Connected now." : "Away. A voice waits for it, for up to a day."
    }

    private func refresh() {
        microphone = VoiceSyncController.microphoneAllowed
        speech = VoiceSyncController.speechAllowed
        canTranscribe = VoiceRecorder.recognizer() != nil
        voice.refreshDestinations()
    }

    @ViewBuilder
    private func permission(_ allowed: Bool?, ask: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        switch allowed {
        case true?: StatusBadge("Allowed", .success)
        case nil: Button("Allow…", action: ask).buttonStyle(.pill)
        case false?: Button("Open Settings…", action: settings).buttonStyle(.pill)
        }
    }

    private static func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Not observing `voice`: its level changes many times a second while recording, and every row would follow it.
private struct VoiceRow: View {
    let record: VoiceRecord
    let voice: VoiceSyncController
    let playing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: record.direction == .received ? "arrow.down.left.circle" : "arrow.up.right.circle")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityLabel(record.direction == .received ? "Received" : "Sent")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(record.direction == .received ? "From" : "To") \(record.peer.label)")
                    .font(Theme.Fonts.rowEmphasis)
                Text([record.recordedAt.formatted(date: .abbreviated, time: .shortened), VoiceFormat.clock(record.seconds)]
                    .joined(separator: " · "))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: record.text ?? "No transcript")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(record.text == nil ? .tertiary : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Space.sm)
            Button {
                voice.togglePlay(record)
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(playing ? "Stop" : "Play")
            Menu {
                if record.text != nil { Button("Copy Text") { voice.copyText(record) } }
                Button("Copy Audio") { voice.copyAudio(record) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([voice.audioURL(for: record)]) }
                Divider()
                Button("Delete", role: .destructive) { voice.delete(record) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for this voice")
        }
        .settingsRowPadding()
    }
}
