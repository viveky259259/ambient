import AmbientCore
import AppKit
import SwiftUI

/// Plays what goes to the Ambient speaker on another Mac, and lets other Macs play theirs here.
struct SpeakerPane: View {
    @ObservedObject var speaker: SpeakerController
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    @State private var microphone = VoiceSyncController.microphoneAllowed

    /// Paired machines it can play on: the ones reached by plain ssh.
    private var machines: [RemoteLinkStatus] {
        model.remoteLinks.filter { SpeakerController.host(of: $0.machine) != nil }
    }

    private var destination: String? {
        prefs.speakerDestination.flatMap { id in machines.first { $0.machine.id == id }?.machine.id }
            ?? machines.first?.machine.id
    }

    private var hasSpeaker: Bool { [.installed, .outdated].contains(speaker.driver) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SettingsSection(header: "Play on another Mac",
                            footer: "Choose Ambient as the output in Sound settings, or in the app that plays. ⏯ on the other Mac plays and pauses here.") {
                SettingsRow(title: "Play on", subtitle: machines.isEmpty ? "Pair a Mac in Agents › Other Machines." : nil) {
                    if machines.isEmpty {
                        StatusBadge("No Mac yet", .neutral)
                    } else {
                        Picker("Play on", selection: Binding(get: { destination ?? "" }, set: choose)) {
                            ForEach(machines, id: \.machine.id) { link in
                                Text(verbatim: link.health == .connected ? link.machine.label : "\(link.machine.label) (away)")
                                    .tag(link.machine.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsDivider()
                SettingsToggleRow(title: "Play Ambient's sound there", subtitle: status?.text,
                                  subtitleStatus: status?.kind ?? .neutral,
                                  isOn: Binding(get: { prefs.speakerOn }, set: { on in
                                      if on, let destination { speaker.start(on: destination) } else { speaker.stop() }
                                  }))
                    .disabled(!prefs.speakerOn && (!hasSpeaker || destination == nil))
            }
            SettingsSection(header: "This Mac") {
                SettingsRow(title: "Ambient speaker", subtitle: driverNote?.text, subtitleStatus: driverNote?.kind ?? .neutral) {
                    driverControl
                }
                SettingsDivider()
                SettingsRow(title: "Microphone", subtitle: "Picks up only what plays to the Ambient speaker.") {
                    switch microphone {
                    case true?: StatusBadge("Allowed", .success)
                    case nil: Button("Allow…") { VoiceSyncController.askForMicrophone { microphone = $0 } }.buttonStyle(.pill)
                    case false?:
                        Button("Open Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.pill)
                    }
                }
                SettingsDivider()
                SettingsToggleRow(title: "Play sound from other Macs",
                                  subtitle: "Lets your other Macs play their Ambient speaker here.",
                                  isOn: $prefs.speakerReceive)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        speaker.refresh()
        microphone = VoiceSyncController.microphoneAllowed
    }

    private func choose(_ id: String) {
        if prefs.speakerOn { speaker.start(on: id) } else { prefs.speakerDestination = id }
    }

    private var status: (text: String, kind: Theme.Status)? {
        switch speaker.stream {
        case .off: nil
        case .connecting(let label): ("Connecting to \(label)…", .neutral)
        case .playing(let device, let lateMs?, let videoWaitsMs):
            videoWaitsMs == nil
                ? ("\(device) plays it \(lateMs) ms late. Update the Ambient speaker for video to wait for it.", .warning)
                : ("\(device) plays it \(lateMs) ms late, and video here waits for it.", .success)
        case .playing(let device, nil, _): ("Playing on \(device).", .success)
        case .waiting(let reason): ("\(reason) Trying again shortly.", .warning)
        case .stopped(let reason): (reason, .warning)
        }
    }

    private var driverNote: (text: String, kind: Theme.Status)? {
        switch speaker.driver {
        case .unavailable: ("This build doesn't include it: build the app with scripts/build-app.sh.", .neutral)
        case .missing: ("Adds Ambient to this Mac's outputs. macOS asks for your password, and the sound stops for a moment.", .neutral)
        case .outdated: ("This version of Ambient has a newer one.", .warning)
        case .failed(let message): (message, .error)
        case .installed, .working: nil
        }
    }

    @ViewBuilder private var driverControl: some View {
        switch speaker.driver {
        case .unavailable: StatusBadge("Not included", .neutral)
        case .missing, .failed: Button("Install…") { speaker.install() }.buttonStyle(.pillProminent)
        case .outdated: Button("Update…") { speaker.install() }.buttonStyle(.pillProminent)
        case .working: ProgressView().controlSize(.small)
        case .installed:
            HStack(spacing: Theme.Space.xs) {
                StatusBadge("Installed", .success)
                Menu {
                    Button("Remove the Ambient Speaker…", role: .destructive) { speaker.remove() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Actions for the Ambient speaker")
            }
        }
    }
}
