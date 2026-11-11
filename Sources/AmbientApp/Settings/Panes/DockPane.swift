import SwiftUI

struct DockPane: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            DockGlowPreview(enabled: prefs.dockGlowEnabled, intensity: prefs.dockGlowIntensity)
            SettingsSection {
                SettingsToggleRow(title: "Glow along the Dock", isOn: $prefs.dockGlowEnabled)
                SettingsDivider()
                Group {
                    SettingsRow(title: "Intensity") {
                        HStack(spacing: Theme.Space.xs) {
                            Image(systemName: "sun.min").foregroundStyle(.secondary)
                            Slider(value: $prefs.dockGlowIntensity, in: 0.3...1.5) { Text("Intensity") }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 180)
                            Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: "Light up behind the Dock's glass",
                                subtitle: "Needs Accessibility access to find the Dock. Without it, Ambient draws a light along the screen edge.") {
                        PermissionControl(allowed: setup.accessibilityTrusted ? true : nil, ask: { setup.requestAccessibility() },
                                          openSettings: { setup.requestAccessibility() })
                    }
                }
                .disabled(!prefs.dockGlowEnabled)
            }
        }
    }
}
