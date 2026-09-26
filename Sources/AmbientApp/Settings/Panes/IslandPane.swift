import SwiftUI

struct IslandPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .island)
            IslandPreview(enabled: prefs.islandEnabled, showsWorking: prefs.islandShowsWorking)
            SettingsSection {
                SettingsToggleRow(title: "Show agent status at the notch", isOn: $prefs.islandEnabled)
                SettingsDivider()
                SettingsToggleRow(title: "Show while agents are working",
                                  subtitle: "Otherwise the island appears only when an agent needs you, finishes, or fails.",
                                  isOn: $prefs.islandShowsWorking)
                    .disabled(!prefs.islandEnabled)
            }
        }
    }
}
