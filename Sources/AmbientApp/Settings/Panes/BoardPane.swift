import AmbientCore
import SwiftUI

/// Native Kanban-style board of agent tasks (metadata-only grouping).
struct BoardPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .board)
            if model.tasks.isEmpty {
                SettingsSection(footer: "Tasks appear as your agents work, grouped by project and title. Or add one with `ambient task upsert --title \"…\"`.") {
                    Text("No tasks yet")
                        .font(Theme.Fonts.row)
                        .foregroundStyle(.secondary)
                        .settingsRowPadding()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        ForEach(TaskStatus.boardOrder.filter { status in
                            model.tasks.contains { $0.status == status }
                        }, id: \.self) { status in
                            BoardColumn(status: status,
                                        tasks: model.tasks.filter { $0.status == status },
                                        sessions: model.sessions,
                                        open: { model.openTask($0) })
                        }
                    }
                    .padding(.bottom, Theme.Space.xs)
                }
            }
        }
    }
}

private struct BoardColumn: View {
    let status: TaskStatus
    let tasks: [AgentTask]
    let sessions: [Session]
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(status.displayName)
                    .font(Theme.Fonts.sectionHeader)
                Spacer(minLength: 0)
                Text("\(tasks.count)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.xxs)

            VStack(spacing: Theme.Space.xs) {
                ForEach(tasks) { task in
                    BoardCard(task: task, session: linkedSession(task), open: { open(task.id) })
                }
            }
        }
        .frame(width: 200, alignment: .topLeading)
    }

    private func linkedSession(_ task: AgentTask) -> Session? {
        if let id = task.lastSessionId, let s = sessions.first(where: { $0.id == id }) { return s }
        return sessions.first { task.sessionIds.contains($0.id) }
    }
}

private struct BoardCard: View {
    let task: AgentTask
    let session: Session?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(Theme.Fonts.rowEmphasis)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let project = task.project {
                    Text(project)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    ForEach(task.agents, id: \.self) { agent in
                        Circle()
                            .fill(Palette.agent(agent).color)
                            .frame(width: 8, height: 8)
                            .help(agent.displayName)
                    }
                    Text(task.agentLabel)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let session {
                        Circle()
                            .fill(session.moodTint.color)
                            .frame(width: 8, height: 8)
                            .help(Describe.mood(session.mood))
                    }
                }
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline.opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(session == nil && task.sessionIds.isEmpty)
        .help(session == nil ? "No live session to open" : "Open \(session!.agentLabel)")
    }
}
