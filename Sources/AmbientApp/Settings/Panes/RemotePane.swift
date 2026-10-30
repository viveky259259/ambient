import AmbientCore
import AppKit
import SwiftUI

/// Paired machines and how their links are doing. Pairing runs in the terminal, where the user's ssh can ask them
/// anything it needs to.
struct RemotePane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    let remote: RemoteCoordinator
    @State private var copied = false
    @State private var confirmingPurge: Machine?

    private static let addCommand = "ambient remote add NAME"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .remote)
            SettingsSection(header: "Machines",
                            footer: model.remoteLinks.isEmpty ? nil : "A session shows as Unknown while its machine can't be reached, and a prompt that waited while this Mac slept shows as Missed.") {
                if model.remoteLinks.isEmpty {
                    Text("No machines paired yet.")
                        .font(Theme.Fonts.row)
                        .foregroundStyle(.secondary)
                        .settingsRowPadding()
                }
                ForEach(Array(model.remoteLinks.enumerated()), id: \.element.machine.id) { index, link in
                    if index > 0 { SettingsDivider() }
                    MachineRow(link: link, remove: { remote.remove(link.machine.id) }, purge: { confirmingPurge = link.machine })
                }
            }
            SettingsSection(header: "Add a machine",
                            footer: "This runs your own ssh, with your own config, keys and bastions. It copies a small shell script from this app to the machine, checks its checksum, adds hooks for Claude Code and Codex, and pins the machine's identity. Use `-- COMMAND` for any other transport, and `ambient doctor --remote NAME` to check a link.") {
                HStack(spacing: Theme.Space.sm) {
                    Text(Self.addCommand).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Spacer(minLength: Theme.Space.sm)
                    Button(copied ? "Copied" : "Copy", action: copy).buttonStyle(.pill)
                }
                .settingsRowPadding()
            }
            SettingsSection(header: "Privacy",
                            footer: "Text from other machines stays on this Mac. It never reaches online voices or any address but this Mac's own.") {
                SettingsToggleRow(title: "Summarize remote sessions with the local LLM",
                                  subtitle: "Off keeps their text away from the board's summarizer, too.",
                                  isOn: Binding(get: { prefs.remoteSummaries }, set: {
                                      prefs.remoteSummaries = $0
                                      remote.policyChanged("remoteSummaries=\($0 ? "on" : "off")")
                                  }))
            }
        }
        .confirmationDialog("Delete everything from \(confirmingPurge?.label ?? "this machine")?",
                            isPresented: Binding(get: { confirmingPurge != nil }, set: { if !$0 { confirmingPurge = nil } }),
                            titleVisibility: .visible) {
            Button("Unpair and Delete", role: .destructive) {
                if let machine = confirmingPurge { remote.purge(machine.id) }
                confirmingPurge = nil
            }
        } message: {
            Text("Its sessions, cursor, board tasks and today's moments go from this Mac. Its hooks stay on the machine until you run `ambient remote remove --uninstall` first.")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.addCommand, forType: .string)
        copied = true
    }
}

private struct MachineRow: View {
    let link: RemoteLinkStatus
    let remove: () -> Void
    let purge: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Circle()
                .fill((link.health == .connected ? Palette.done : Palette.idle).color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: link.machine.label).font(Theme.Fonts.rowEmphasis)
                Text(link.summary).font(Theme.Fonts.caption).foregroundStyle(.secondary)
                Text(verbatim: link.machine.transport.joined(separator: " "))
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: link.machine.fingerprint)
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let detail = link.health.detail {
                    Text(verbatim: detail)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Status.warning.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            Menu {
                Button("Remove", action: remove)
                Button("Delete Everything from This Machine…", role: .destructive, action: purge)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(link.machine.label)")
        }
        .settingsRowPadding()
    }
}
