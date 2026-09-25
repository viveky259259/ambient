import AmbientCore
import SwiftUI

struct AlertsPane: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    let onPreviewSound: (Mood) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .alerts)
            NotificationPreview(enabled: prefs.notificationsEnabled, chimesOn: prefs.soundsEnabled, onPlay: onPreviewSound)
            SettingsSection(header: "Notifications",
                            footer: "Ambient stays quiet while you're already in the app running the agent.") {
                SettingsRow(title: "Show notifications", subtitle: "When an agent needs you, finishes, or fails.") {
                    HStack(spacing: Theme.Space.sm) {
                        permission
                        Toggle("Show notifications", isOn: $prefs.notificationsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Announce finished turns longer than") {
                    Picker("Announce finished turns longer than", selection: $prefs.doneThreshold) {
                        Text("Always").tag(0.0)
                        Text("10 seconds").tag(10.0)
                        Text("20 seconds").tag(20.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsSection(header: "Sound") {
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
        }
    }

    @ViewBuilder private var permission: some View {
        switch setup.notificationStatus {
        case .authorized, .provisional:
            StatusBadge("Allowed", .success)
        case .denied:
            Button("Open System Settings") { setup.requestNotifications() }.buttonStyle(.pill)
        default:
            Button("Allow") { setup.requestNotifications() }.buttonStyle(.pill)
        }
    }
}
