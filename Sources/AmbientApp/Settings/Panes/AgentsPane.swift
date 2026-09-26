import AmbientCore
import SwiftUI

/// Connect, update or remove Ambient's hooks for each agent.
struct AgentsPane: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .agents)
            SettingsSection(footer: "Ambient adds background hooks that never slow your agent down, keeps a backup of every file it edits, and removes only its own entries.") {
                ForEach(Array(AgentKind.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { SettingsDivider() }
                    AgentRow(agent: agent,
                             state: setup.agentStates[agent] ?? .notInstalled,
                             error: setup.agentErrors[agent],
                             path: setup.installer.configURL(agent).path
                                 .replacingOccurrences(of: setup.paths.userHome.path, with: "~"),
                             install: { setup.install(agent) },
                             uninstall: { setup.uninstall(agent) })
                }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentKind
    let state: InstallState
    let error: String?
    let path: String
    let install: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle().fill(Palette.agent(agent).color.opacity(0.16))
                Circle().fill(Palette.agent(agent).color).frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.rowEmphasis)
                Text(path).font(Theme.Fonts.mono).foregroundStyle(.secondary).textSelection(.enabled)
                if agent == .codex, state == .installed {
                    Text("Codex runs new hooks only after you approve them: type /hooks in Codex once.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Status.warning.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Status.error.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            badge
            action
        }
        .settingsRowPadding()
    }

    private var title: String {
        switch agent {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }

    private var badge: StatusBadge {
        switch state {
        case .installed: StatusBadge("Connected", .success)
        case .partial: StatusBadge("Needs update", .warning)
        case .notInstalled: StatusBadge("Not connected", .neutral)
        case .agentMissing: StatusBadge("Not found", .neutral)
        case .unreadable: StatusBadge("Config unreadable", .error)
        }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .installed: Button("Remove", action: uninstall).buttonStyle(.pill)
        case .partial: Button("Update", action: install).buttonStyle(.pillProminent)
        case .notInstalled: Button("Connect", action: install).buttonStyle(.pillProminent)
        case .agentMissing, .unreadable: EmptyView()
        }
    }
}
