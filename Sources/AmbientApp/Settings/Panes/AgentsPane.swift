import AmbientCore
import AppKit
import SwiftUI

/// Connect, update or remove Ambient's hooks for each agent.
struct AgentsPane: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SettingsSection(footer: "Ambient adds background hooks that never slow your agent down, keeps a backup of every file it edits, and removes only its own entries.") {
                ForEach(Array(AgentKind.hooked.enumerated()), id: \.element) { index, agent in
                    if index > 0 { SettingsDivider() }
                    AgentRow(agent: agent,
                             state: setup.agentStates[agent] ?? .notInstalled,
                             error: setup.agentErrors[agent],
                             path: (setup.installer.configURL(agent)?.path ?? "")
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
                // The config file it edits is in the tooltip and the context menu, not in the way.
                HStack(spacing: Theme.Space.xs) {
                    Text(title).font(Theme.Fonts.rowEmphasis).help(path)
                    if agent.isBeta { StatusBadge("Beta", .neutral) }
                }
                if let note {
                    Text(note)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .contextMenu {
            if !path.isEmpty {
                Button("Copy Config File Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                Button("Show Config File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
                }
            }
        }
    }

    private var title: String {
        switch agent {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .copilot: "Copilot CLI"
        case .opencode: "OpenCode"
        case .custom: "Custom agent"
        }
    }

    /// What a partial or beta connection shows, and what it can't. Beta shows as a badge by the name.
    private var note: String? {
        switch agent {
        case .antigravity: "Prompts, tools and finished or failed turns. It never shows as needing you: Antigravity has no permission hook."
        case .opencode: "OpenCode 1.4 or later. OpenCode 2 runs plugins in its background service, so a click can't bring back its terminal."
        case .cursor: "Prompts, tools (as they finish), subagents and finished turns. It never shows as needing you: Ambient uses no hook that could block Cursor."
        case .copilot: "Prompts, tools, permission prompts, questions, subagents and errors."
        default: nil
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
