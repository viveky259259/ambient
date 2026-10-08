import AmbientCore
import SwiftUI

struct PetPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .pet)
            PetPreview(enabled: prefs.petEnabled, species: prefs.pet)
            SettingsSection(footer: "Hover the pet for your sessions and actions, click it for a quick look at all of them, and click a session to jump to it. Drag it anywhere.") {
                SettingsToggleRow(title: "Show the pet on your desktop",
                                  subtitle: "Works with or without the notch island.",
                                  isOn: $prefs.petEnabled)
                SettingsDivider()
                Group {
                    SettingsRow(title: "Pet") {
                        Picker("Pet", selection: $prefs.petSpecies) {
                            ForEach(PetSpecies.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow(title: "Position", subtitle: "The bottom-right corner of the screen with the menu bar.") {
                        Button("Reset") { prefs.petOrigin = nil }
                            .buttonStyle(.pill)
                            .disabled(prefs.petOrigin == nil)
                    }
                }
                .disabled(!prefs.petEnabled)
            }
        }
    }
}
