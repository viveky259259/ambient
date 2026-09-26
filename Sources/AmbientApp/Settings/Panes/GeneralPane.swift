import AmbientCore
import AppKit
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var setup: SetupModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .general)
            SettingsSection {
                SettingsToggleRow(title: "Open Ambient at login",
                                  subtitle: setup.loginItemNeedsApproval
                                      ? "Approve Ambient in System Settings › General › Login Items." : nil,
                                  subtitleStatus: .warning,
                                  isOn: Binding(get: { setup.launchAtLogin }, set: { setup.setLaunchAtLogin($0) }))
            }
            SettingsSection(header: "Command-line tool",
                            footer: "Try `ambient doctor` or `ambient status`. Add `~/.ambient/bin` to your PATH to use it anywhere.") {
                HStack(spacing: Theme.Space.sm) {
                    Text(cliPath)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: Theme.Space.sm)
                    Button(copied ? "Copied" : "Copy", action: copy).buttonStyle(.pill)
                }
                .settingsRowPadding()
            }
            SettingsSection(header: "About") {
                SettingsRow(title: "Version") {
                    Text(AmbientVersion.current).font(Theme.Fonts.row).foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(title: "Source code") {
                    Link("github.com/viveky259259/ambient",
                         destination: URL(string: "https://github.com/viveky259259/ambient")!)
                        .font(Theme.Fonts.row)
                }
                SettingsDivider()
                SettingsRow(title: "License") {
                    Text("MIT").font(Theme.Fonts.row).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cliPath: String {
        setup.paths.cliLink.path.replacingOccurrences(of: setup.paths.userHome.path, with: "~")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setup.paths.cliLink.path, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
