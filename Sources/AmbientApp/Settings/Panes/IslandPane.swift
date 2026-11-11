import AmbientCore
import SwiftUI

/// What the notch shows. Answering permission prompts there is in Alerts, with the other moments that need you.
struct IslandPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            IslandPreview(enabled: prefs.islandEnabled, showsWorking: prefs.islandShowsWorking)
            SettingsSection {
                SettingsToggleRow(title: "Show agent status at the notch",
                                  subtitle: "Voices you record or receive show there either way.",
                                  isOn: $prefs.islandEnabled)
                SettingsDivider()
                SettingsToggleRow(title: "Show while agents are working",
                                  subtitle: "Otherwise it shows only when an agent needs you, finishes, or fails.",
                                  isOn: $prefs.islandShowsWorking)
                    .disabled(!prefs.islandEnabled)
            }
        }
    }
}
