import AmbientCore
import SwiftUI

struct AlertsPane: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    let onPreviewSound: (Mood) -> Void
    @State private var hookProblem: String?

    private static let finishedTurns: [(seconds: Double, label: String)] = [
        (0, "All of them"), (10, "Longer than 10 seconds"), (20, "Longer than 20 seconds"), (60, "Longer than 1 minute"),
        (300, "Longer than 5 minutes"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .alerts)
            NotificationPreview(enabled: prefs.notificationsEnabled, chimesOn: prefs.soundsEnabled, onPlay: onPreviewSound)
            SettingsSection(header: "Notifications",
                            footer: "Ambient stays quiet while you're already in the app running the agent.") {
                SettingsRow(title: "Show notifications", subtitle: "When an agent needs you, finishes, or fails.") {
                    HStack(spacing: Theme.Space.sm) {
                        PermissionControl(allowed: notificationsAllowed, ask: setup.requestNotifications,
                                          openSettings: setup.requestNotifications)
                        Toggle("Show notifications", isOn: $prefs.notificationsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Tell me about finished turns", subtitle: "For banners and chimes.") {
                    Picker("Tell me about finished turns", selection: $prefs.doneThreshold) {
                        ForEach(Self.finishedTurns, id: \.seconds) { Text($0.label).tag($0.seconds) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsSection(header: "Chimes") {
                SettingsToggleRow(title: "Play chimes", isOn: $prefs.soundsEnabled)
                SettingsDivider()
                SettingsRow(title: "Volume") {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $prefs.soundVolume, in: 0...1) { editing in
                            if !editing { onPreviewSound(.done) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 180)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Volume")
                }
                .disabled(!prefs.soundsEnabled)
            }
            SettingsSection(header: "Permission prompts",
                            footer: "Ambient never answers for you. Changing this edits a Codex hook: type /hooks in Codex once to approve it.") {
                SettingsToggleRow(title: "Answer from the notch",
                                  subtitle: prefs.islandEnabled
                                      ? "Allow once or Deny Claude Code and Codex requests at the notch."
                                      : "Turn on Show agent status in Appearance › Notch first.",
                                  isOn: $prefs.answerPermissions)
                    .disabled(!prefs.islandEnabled)
                SettingsDivider()
                SettingsRow(title: "Wait for an answer", subtitle: "Then the agent asks you as usual.") {
                    Picker("Wait for an answer", selection: $prefs.permissionWait) {
                        ForEach(PermissionSettings.waits, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!prefs.answerPermissions || !prefs.islandEnabled)
                if let hookProblem {
                    Text(hookProblem)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Status.error.textColor)
                        .settingsRowPadding()
                }
            }
        }
        .onChange(of: prefs.permissionSettings) { _, settings in hookProblem = PermissionHooks.apply(settings) }
    }

    private var notificationsAllowed: Bool? {
        switch setup.notificationStatus {
        case .authorized, .provisional: true
        case .denied: false
        default: nil
        }
    }
}
