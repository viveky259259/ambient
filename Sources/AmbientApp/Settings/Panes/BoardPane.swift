import AmbientCore
import SwiftUI

/// Native Kanban-style board of agent tasks, with optional local-LLM summaries.
struct BoardPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    /// Opens the dedicated full Board window (Settings keeps a compact pane).
    var onOpenBoard: (() -> Void)? = nil
    @State private var llmExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .board)
            boardChrome
            llmSection
            wallpaperBoardToggle
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
        .onAppear { model.refreshTaskLLMStatus() }
    }

    private var boardChrome: some View {
        SettingsSection(footer: "The full Board is a wider window for scanning columns. Settings keeps this compact view.") {
            SettingsRow(title: "Full Board window") {
                Button("Open Board") { onOpenBoard?() }
                    .buttonStyle(.pillProminent)
                    .disabled(onOpenBoard == nil)
            }
        }
    }

    private var wallpaperBoardToggle: some View {
        SettingsSection(
            header: "Living wallpaper",
            footer: "Soft title + status cues on the desk scene — not a Kanban dump. Off by default, like calendar and lock-message overlays. Hidden when there are no blocked or in-progress tasks."
        ) {
            SettingsToggleRow(
                title: "Show task board on wallpaper",
                subtitle: prefs.wallpaperEnabled ? nil : "Turn on Living wallpaper in Settings › Wallpaper first.",
                isOn: $prefs.wallpaperShowBoard
            )
            .disabled(!prefs.wallpaperEnabled)
        }
    }

    private var llmSection: some View {
        SettingsSection(
            header: "Local LLM",
            footer: llmExpanded
                ? "Uses the local-agent MCP gateway on this Mac (`http://127.0.0.1:5051/mcp`). Session text stays on-device — non-loopback URLs are refused. Cloud-tagged models are blocked. Optional one-shot skill pack (`ambient task skill-bootstrap`) teaches better titles via Keychain Anthropic, then runtime stays local. If `/Volumes/Models` is missing, run `models-on`. Metadata heuristics still run when the LLM is off or unavailable."
                : "On-device titles via local-agent MCP. Expand for model, transcripts, and gateway options."
        ) {
            SettingsToggleRow(
                title: "Summarize tasks with local LLM",
                subtitle: model.taskLLMStatus.label,
                subtitleStatus: subtitleStatus(model.taskLLMStatus),
                isOn: $prefs.taskLLMEnabled
            )
            .onChange(of: prefs.taskLLMEnabled) { _, _ in model.refreshTaskLLMStatus() }
            SettingsDivider()
            DisclosureGroup(isExpanded: $llmExpanded) {
                SettingsToggleRow(
                    title: "Read local transcripts",
                    subtitle: "Opt-in. When on, Ambient may read Claude project JSONL (and Codex thread names) for richer summaries. Still local only — may include secrets from those chats.",
                    isOn: $prefs.taskLLMReadTranscripts
                )
                SettingsDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model id").font(Theme.Fonts.caption).foregroundStyle(.secondary)
                    TextField("hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit", text: $prefs.taskLLMModelID)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.mono)
                    Text("MCP URL (loopback only)").font(Theme.Fonts.caption).foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:5051/mcp", text: $prefs.taskLLMMCPURL)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.mono)
                    Text("Models volume").font(Theme.Fonts.caption).foregroundStyle(.secondary)
                    TextField("/Volumes/Models", text: $prefs.taskLLMModelsVolume)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.mono)
                    Text(skillPackCaption)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Check status") { model.refreshTaskLLMStatus() }
                            .buttonStyle(.pill)
                        Spacer()
                    }
                }
                .settingsRowPadding()
            } label: {
                Text(llmExpanded ? "Hide advanced options" : "Model & gateway options")
                    .font(Theme.Fonts.row)
                    .foregroundStyle(.secondary)
                    .settingsRowPadding()
            }
        }
    }

    private func subtitleStatus(_ status: TaskLLMStatus) -> Theme.Status {
        switch status {
        case .ready, .summarizing: .success
        case .disabled: .neutral
        case .gatewayDown, .volumeMissing, .modelUnavailable, .cloudModelBlocked, .nonLoopbackBlocked, .failed: .warning
        }
    }

    private var skillPackCaption: String {
        if TaskSkillStore.exists() {
            let pack = TaskSkillStore.load()
            return "Skill pack: \(pack.source) · \(pack.examples.count) examples (~/.ambient/task-skill.json)"
        }
        return "Skill pack: bundled seed. Optional: ambient task skill-bootstrap (Keychain Anthropic once)."
    }
}

/// Full-window board: wider columns, same cards, no Settings chrome.
struct BoardWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Board")
                        .font(Theme.Fonts.paneTitle)
                    Text(model.taskLLMStatus.label)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("Wallpaper cues", isOn: $prefs.wallpaperShowBoard)
                    .toggleStyle(.switch)
                    .disabled(!prefs.wallpaperEnabled)
                    .help("Soft task titles on the living wallpaper. Off by default.")
            }
            if model.tasks.isEmpty {
                Text("No tasks yet — they appear as your agents work.")
                    .font(Theme.Fonts.row)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        ForEach(TaskStatus.boardOrder.filter { status in
                            model.tasks.contains { $0.status == status }
                        }, id: \.self) { status in
                            BoardColumn(status: status,
                                        tasks: model.tasks.filter { $0.status == status },
                                        sessions: model.sessions,
                                        open: { model.openTask($0) },
                                        wide: true)
                        }
                    }
                    .padding(.bottom, Theme.Space.sm)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(minWidth: 880, minHeight: 520)
        .onAppear { model.refreshTaskLLMStatus() }
    }
}

private struct BoardColumn: View {
    let status: TaskStatus
    let tasks: [AgentTask]
    let sessions: [Session]
    let open: (String) -> Void
    var wide: Bool = false

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

            // Lazy: a long-lived board holds thousands of tasks, and only the ones on screen should cost anything.
            LazyVStack(spacing: Theme.Space.xs) {
                ForEach(tasks) { task in
                    BoardCard(task: task, session: linkedSession(task), open: { open(task.id) })
                }
            }
        }
        .frame(width: wide ? 260 : 220, alignment: .topLeading)
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
                // Calm card: one muted summary line (local LLM) or project tag — not a wall of text.
                if let summary = task.summary, !summary.isEmpty {
                    Text(Trim.truncate(summary, max: 60))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let project = task.project {
                    Text(project)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    ForEach(task.agents, id: \.self) { agent in
                        Circle()
                            .fill(Palette.agent(agent).color)
                            .frame(width: 6, height: 6)
                            .help(agent.displayName)
                    }
                    if let project = task.project, task.summary != nil {
                        Text(project)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else {
                        Text(task.agentLabel)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let session, let clock = Describe.clock(session, now: Date()) {
                        Text(clock)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if task.summarySource == .localLLM {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .help("Summarized by local LLM")
                    }
                    if let session {
                        Circle()
                            .fill(session.moodTint.color)
                            .frame(width: 6, height: 6)
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
