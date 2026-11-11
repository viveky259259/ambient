import AmbientCore
import AppKit
import SwiftUI

/// Plays this Mac's sound on another Mac, through the Ambient speaker, and lets other Macs play theirs here.
struct SpeakerPane: View {
    @ObservedObject var speaker: SpeakerController
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    @State private var microphone = VoiceSyncController.microphoneAllowed
    @AppStorage("settingsPane") private var paneName = SettingsPane.welcome.rawValue
    @AppStorage("settingsTab.agents") private var agentsTab = AgentsTab.thisMac

    /// Paired machines it can play on: the ones reached by plain ssh.
    private var machines: [RemoteLinkStatus] {
        model.remoteLinks.filter { SpeakerController.host(of: $0.machine) != nil }
    }

    private var destination: String? {
        prefs.speakerDestination.flatMap { id in machines.first { $0.machine.id == id }?.machine.id }
            ?? machines.first?.machine.id
    }

    /// The first thing still to do before it can play.
    private var missingStep: String? {
        if !speaker.driver.isInstalled { return "Install the Ambient speaker first." }
        if microphone != true { return "Allow the microphone first." }
        if destination == nil { return "Pair a Mac first." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SettingsSection(header: "Send", footer: "⏯ on the other Mac plays and pauses here.") {
                SettingsRow(title: "Ambient speaker", subtitle: driverNote?.text, subtitleStatus: driverNote?.kind ?? .neutral) {
                    driverControl
                }
                SettingsDivider()
                SettingsRow(title: "Microphone", subtitle: "Picks up only what plays to the Ambient speaker.") {
                    PermissionControl(allowed: microphone, ask: {
                        VoiceSyncController.askForMicrophone { allowed in
                            microphone = allowed
                            speaker.refresh()
                        }
                    }, openSettings: { PermissionControl.openPrivacy("Privacy_Microphone") })
                }
                SettingsDivider()
                SettingsRow(title: "Play on", subtitle: pairingNote) {
                    if machines.isEmpty {
                        Button("Show Other Machines") {
                            agentsTab = .otherMachines
                            paneName = SettingsPane.agents.rawValue
                        }
                        .buttonStyle(.pill)
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
                SettingsToggleRow(title: "Play this Mac's sound there", subtitle: status?.text,
                                  subtitleStatus: status?.kind ?? .neutral,
                                  isOn: Binding(get: { prefs.speakerOn }, set: { on in
                                      if on, let destination { speaker.start(on: destination) } else { speaker.stop() }
                                  }))
                    .disabled(!prefs.speakerOn && missingStep != nil)
                if prefs.speakerOn {
                    SettingsDivider()
                    SettingsRow(title: "Output",
                                subtitle: speaker.outputIsAmbient ? "Ambient is this Mac's output."
                                    : "This Mac's sound still goes to \(speaker.outputName).") {
                        if speaker.outputIsAmbient {
                            StatusBadge("Ambient", .success)
                        } else {
                            Button("Use Ambient") { speaker.useAmbient() }.buttonStyle(.pillProminent)
                        }
                    }
                }
                if showsDetail, let detail = speaker.detail {
                    DetailsDisclosure {
                        Text(verbatim: detail)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .settingsRowPadding()
                }
            }
            SettingsSection(header: "Receive") {
                SettingsToggleRow(title: "Play sound from other Macs",
                                  subtitle: "Lets your other Macs play their sound here.",
                                  isOn: $prefs.speakerReceive)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        microphone = VoiceSyncController.microphoneAllowed
        speaker.refresh()
    }

    private func choose(_ id: String) {
        if prefs.speakerOn { speaker.start(on: id) } else { prefs.speakerDestination = id }
    }

    private var pairingNote: String? {
        guard machines.isEmpty else { return nil }
        if let custom = model.remoteLinks.first?.machine.label {
            return "\(custom) is paired with a custom command, so the speaker can't play there."
        }
        return "Pair the Mac you want to play on, from this Mac."
    }

    private var showsDetail: Bool {
        switch speaker.stream {
        case .waiting, .stopped: true
        default: false
        }
    }

    private var status: (text: String, kind: Theme.Status)? {
        switch speaker.stream {
        case .off:
            return missingStep.map { ($0, .neutral) }
        case .connecting(let label):
            return ("Connecting to \(label)…", .neutral)
        case .connected(let label, let device, let lateMs, let videoWaitsMs):
            guard speaker.outputIsAmbient else {
                return ("Connected to \(label). Choose Ambient as this Mac's output to play there.", .neutral)
            }
            guard let lateMs else { return ("Playing on \(device).", .success) }
            return videoWaitsMs == nil
                ? ("Playing on \(device), \(lateMs) ms behind. Update the Ambient speaker so video waits to match.", .warning)
                : ("Playing on \(device), \(lateMs) ms behind. Video here waits to match.", .success)
        case .waiting(let reason, let seconds):
            return ("\(reason) Trying again in \(seconds) seconds.", .warning)
        case .stopped(let reason):
            return (reason, .warning)
        }
    }

    private var driverNote: (text: String, kind: Theme.Status)? {
        switch speaker.driver {
        case .unavailable: ("This copy of Ambient doesn't come with the speaker.", .neutral)
        case .missing: ("Adds Ambient to this Mac's outputs. macOS asks for your password, and the sound stops for a moment.", .neutral)
        case .outdated: ("A newer Ambient speaker comes with this version of Ambient.", .warning)
        case .installing: ("Installing… Enter your password in the macOS prompt. The sound stops for a moment.", .neutral)
        case .removing: ("Removing…", .neutral)
        case .failed(let message, _): (message, .error)
        case .installed: nil
        }
    }

    @ViewBuilder private var driverControl: some View {
        switch speaker.driver {
        case .unavailable: StatusBadge("Not included", .neutral)
        case .missing: Button("Install…") { speaker.install() }.buttonStyle(.pillProminent)
        case .outdated: Button("Update…") { speaker.install() }.buttonStyle(.pillProminent)
        case .installing, .removing: ProgressView().controlSize(.small)
        case .failed: Button("Try Again…") { speaker.tryAgain() }.buttonStyle(.pill)
        case .installed:
            HStack(spacing: Theme.Space.xs) {
                StatusBadge("Installed", .success)
                Menu {
                    Button("Remove Ambient Speaker…", role: .destructive) { speaker.remove() }
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
