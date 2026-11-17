import AmbientCore
import AppKit
import SwiftUI

/// Uses another Mac's microphone here, as Ambient Microphone, and lends this Mac's to other Macs.
struct MicrophonePane: View {
    @ObservedObject var mic: MicController
    @ObservedObject var speaker: SpeakerController
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    @State private var microphone = VoiceSyncController.microphoneAllowed
    @AppStorage("settingsPane") private var paneName = SettingsPane.welcome.rawValue
    @AppStorage("settingsTab.agents") private var agentsTab = AgentsTab.thisMac

    /// Paired machines whose microphone it can use: the ones reached by ssh.
    private var machines: [RemoteLinkStatus] {
        model.remoteLinks.filter { SpeakerController.route(to: $0.machine) != nil }
    }

    private var source: String? {
        prefs.micSource.flatMap { id in machines.first { $0.machine.id == id }?.machine.id } ?? machines.first?.machine.id
    }

    /// The first thing still to do before it can be used.
    private var missingStep: String? {
        if !mic.available {
            return speaker.driver.isInstalled ? "Update the Ambient driver first." : "Install the Ambient microphone first."
        }
        if source == nil { return "Pair a Mac first." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SettingsSection(header: "Use",
                            footer: "Apps hear it when Ambient Microphone is their microphone. The other Mac's microphone "
                                + "is on only while one does.") {
                AmbientDriverRow(speaker: speaker, title: "Ambient Microphone",
                                 adds: "Adds Ambient Microphone to this Mac's inputs. macOS asks for your password, and "
                                     + "the sound stops for a moment.")
                SettingsDivider()
                SettingsRow(title: "Microphone of", subtitle: pairingNote) {
                    if machines.isEmpty {
                        Button("Show Other Machines") {
                            agentsTab = .otherMachines
                            paneName = SettingsPane.agents.rawValue
                        }
                        .buttonStyle(.pill)
                    } else {
                        Picker("Microphone of", selection: Binding(get: { source ?? "" }, set: choose)) {
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
                SettingsToggleRow(title: "Use its microphone here", subtitle: status?.text,
                                  subtitleStatus: status?.kind ?? .neutral,
                                  isOn: Binding(get: { prefs.micUse }, set: { on in
                                      if on, let source { mic.startUsing(from: source) } else { mic.stopUsing() }
                                  }))
                    .disabled(!prefs.micUse && missingStep != nil)
                if prefs.micUse, mic.available {
                    SettingsDivider()
                    SettingsRow(title: "Input",
                                subtitle: mic.inputIsAmbient ? "Ambient Microphone is this Mac's input."
                                    : "Or choose Ambient Microphone in an app's own settings.") {
                        if mic.inputIsAmbient {
                            StatusBadge("Ambient Microphone", .success)
                        } else {
                            Button("Use as Input") { mic.useAsInput() }.buttonStyle(.pill)
                        }
                    }
                }
                if showsDetail, let detail = mic.detail {
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
            SettingsSection(header: "Lend",
                            footer: "Your other Macs can use this Mac's microphone while Ambient runs here. It records "
                                + "only while one does.") {
                SettingsRow(title: "Microphone") {
                    PermissionControl(allowed: microphone, ask: {
                        VoiceSyncController.askForMicrophone { allowed in
                            microphone = allowed
                            mic.refresh()
                        }
                    }, openSettings: { PermissionControl.openPrivacy("Privacy_Microphone") })
                }
                SettingsDivider()
                SettingsToggleRow(title: "Lend this Mac's microphone", subtitle: lendStatus?.text,
                                  subtitleStatus: lendStatus?.kind ?? .neutral,
                                  isOn: Binding(get: { prefs.micLend }, set: { on in
                                      if on { mic.startLending() } else { mic.stopLending() }
                                  }))
                    .disabled(!prefs.micLend && microphone != true)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        microphone = VoiceSyncController.microphoneAllowed
        speaker.refresh()
        mic.refresh()
    }

    private func choose(_ id: String) {
        if prefs.micUse { mic.startUsing(from: id) } else { prefs.micSource = id }
    }

    private var pairingNote: String? {
        guard machines.isEmpty else { return nil }
        if let custom = model.remoteLinks.first?.machine.label {
            return "\(custom) is paired with a custom command, so its microphone can't be used here."
        }
        return "Pair the Mac whose microphone you want, from this Mac."
    }

    private var showsDetail: Bool {
        switch mic.use {
        case .waiting, .stopped: true
        default: false
        }
    }

    private var status: (text: String, kind: Theme.Status)? {
        switch mic.use {
        case .off:
            return missingStep.map { ($0, .neutral) }
        case .idle(let label):
            return ("Ready. \(label)'s microphone turns on when an app here records from Ambient Microphone.", .neutral)
        case .connecting(let label):
            return ("Connecting to \(label)…", .neutral)
        case .receiving(let label, let device):
            return ("Apps here hear \(label)'s \(device).", .success)
        case .waiting(let reason, let seconds):
            return ("\(reason) Trying again in \(seconds) seconds.", .warning)
        case .stopped(let reason):
            return (reason, .warning)
        }
    }

    private var lendStatus: (text: String, kind: Theme.Status)? {
        switch mic.lend {
        case .off: microphone == true ? nil : ("Allow the microphone first.", .neutral)
        case .ready: ("Your other Macs can use it now.", .neutral)
        case .lending(let to, let device): ("\(to) is using this Mac's \(device).", .success)
        case .stopped(let reason): (reason, .warning)
        }
    }
}
