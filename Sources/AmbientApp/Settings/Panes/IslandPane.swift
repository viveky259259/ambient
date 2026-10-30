import AmbientCore
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
            SettingsSection(footer: "Ambient never answers for you. If you don't answer in time, or you're already in the agent's app, the agent asks you as usual; until then its own prompt waits too. Turning this on or off changes one Codex hook: type /hooks in Codex once to approve it.") {
                SettingsToggleRow(title: "Answer permission prompts from the island",
                                  subtitle: "Allow once or Deny Claude Code and Codex tool requests right at the notch.",
                                  isOn: $prefs.answerPermissions)
                    .disabled(!prefs.islandEnabled)
                SettingsDivider()
                HStack {
                    Text("Wait for an answer")
                    Spacer()
                    Picker("", selection: $prefs.permissionWait) {
                        ForEach(PermissionSettings.waits, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .settingsRowPadding()
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

    @State private var hookProblem: String?
}
