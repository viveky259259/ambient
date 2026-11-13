import AmbientCore
import AppKit
import SwiftUI

/// Native Kanban-style board of agent tasks, with optional local-LLM summaries.
struct BoardPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    /// Opens the dedicated full Board window (Settings keeps a compact pane).
    var onOpenBoard: (() -> Void)? = nil
    /// What was last found at the model path.
    @State private var inspected: (path: String, model: LocalModelPath?)?
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .board)
            boardChrome
            llmSection
            if model.tasks.isEmpty {
                SettingsSection(footer: "Tasks appear as your agents work, grouped by project and title. Or add one with `ambient task upsert --title \"…\"`.") {
                    Text("No tasks yet")
                        .font(Theme.Fonts.row)
                        .foregroundStyle(.secondary)
                        .settingsRowPadding()
                }
            } else {
                BoardSearchField(query: $query)
                let found = TaskSearch.filter(model.tasks, query: query)
                if found.isEmpty {
                    BoardNoMatches(query: query)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            // Each column's latest few only. Inside a sideways ScrollView a column can't be lazy, so a
                            // long-lived board would draw thousands of cards on every agent event.
                            ForEach(TaskBoardColumn.columns(found, limit: Self.cardsPerColumn)) { column in
                                BoardColumn(column: column,
                                            sessions: model.sessions,
                                            notes: model.taskNotes,
                                            open: { model.openTask($0) },
                                            more: onOpenBoard)
                            }
                        }
                        .padding(.bottom, Theme.Space.xs)
                    }
                }
            }
        }
        .onAppear { model.refreshTaskLLMStatus() }
    }

    /// The most cards a column shows here; the Task Board window shows them all.
    static let cardsPerColumn = 8

    private var boardChrome: some View {
        SettingsSection {
            SettingsRow(title: "Task board", subtitle: "Every task your agents are on, by status.") {
                Button("Open Board") { onOpenBoard?() }
                    .buttonStyle(.pillProminent)
                    .disabled(onOpenBoard == nil)
            }
        }
    }

    private var llmSection: some View {
        SettingsSection(header: "Summaries") {
            SettingsToggleRow(
                title: "Summarize tasks on this Mac",
                subtitle: model.taskLLMStatus.label,
                subtitleStatus: subtitleStatus(model.taskLLMStatus),
                isOn: $prefs.taskLLMEnabled
            )
            .onChange(of: prefs.taskLLMEnabled) { _, _ in model.refreshTaskLLMStatus() }
            SettingsDivider()
            SettingsToggleRow(
                title: "Read your agent chats",
                subtitle: "Better titles from your Claude Code and Codex chats on this Mac. They can hold secrets; nothing leaves this Mac.",
                isOn: $prefs.taskLLMReadTranscripts
            )
            .disabled(!prefs.taskLLMEnabled)
            DetailsDisclosure(title: "Model and gateway") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model path").font(Theme.Fonts.caption).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.xs) {
                        TextField("Model folder or .gguf file (optional)", text: $prefs.taskLLMModelPath)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.Fonts.mono)
                        Button("Choose…") { chooseModelPath() }
                            .buttonStyle(.pill)
                        if !prefs.taskLLMModelPath.isEmpty {
                            Button("Clear") { prefs.taskLLMModelPath = "" }
                                .buttonStyle(.pill)
                        }
                    }
                    Text(modelPathCaption)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .task(id: prefs.taskLLMModelPath) { await inspectModelPath() }
                    Text(usesModelPath ? "Model id (unused while a model path is set)" : "Model id")
                        .font(Theme.Fonts.caption).foregroundStyle(.secondary)
                    TextField("hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit", text: $prefs.taskLLMModelID)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.mono)
                        .disabled(usesModelPath)
                    Text("Python for MLX (optional)").font(Theme.Fonts.caption).foregroundStyle(.secondary)
                    TextField("Found automatically", text: $prefs.taskLLMPython)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.mono)
                        .onSubmit { model.refreshTaskLLMStatus() }
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
                    Text("Runs through local-agent on this Mac, or directly with MLX or llama.cpp. Only local models and loopback addresses are allowed; agents can set the model with `ambient mcp`.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Check Status") { model.refreshTaskLLMStatus() }
                            .buttonStyle(.pill)
                        Spacer()
                    }
                }
            }
            .settingsRowPadding()
        }
    }

    private func subtitleStatus(_ status: TaskLLMStatus) -> Theme.Status {
        switch status {
        case .ready, .summarizing: .success
        case .disabled: .neutral
        case .gatewayDown, .volumeMissing, .modelUnavailable, .cloudModelBlocked, .nonLoopbackBlocked, .failed: .warning
        }
    }

    /// The config's own test: spaces alone leave the board on the model id.
    private var usesModelPath: Bool { prefs.taskLLMConfig.usesModelPath }

    /// What the chosen path is and how it runs: through local-agent when it knows the path, else directly.
    private var modelPathCaption: String {
        guard usesModelPath else {
            return "Empty: local-agent runs the model id below. Or choose an MLX or Hugging Face folder, or a .gguf file."
        }
        guard let inspected, inspected.path == prefs.taskLLMModelPath else { return "Checking…" }
        guard let found = inspected.model else { return "Nothing at this path." }
        if let route = model.taskModelRoute, prefs.taskLLMEnabled {
            return "\(found.format.label) · runs \(route.label)"
        }
        return found.format.writesText
            ? "\(found.format.label) · runs through local-agent if it knows this path, else directly with \(found.format.runtime ?? "its runtime")"
            : "\(found.format.label) · can't write summaries"
    }

    /// Once typing pauses, reads what's at the path off the main thread (models often live on an external disk) and
    /// re-probes, so the caption and status describe this path whether or not Return was pressed.
    private func inspectModelPath() async {
        let path = prefs.taskLLMModelPath
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        let found = await Task.detached(priority: .utility) { LocalModelPath.inspect(path) }.value
        guard !Task.isCancelled else { return }
        inspected = (path, found)
        model.refreshTaskLLMStatus()
    }

    private func chooseModelPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        // Hugging Face caches live under ~/.cache.
        panel.showsHiddenFiles = true
        panel.prompt = "Use Model"
        panel.message = "Choose a model folder (config.json and safetensors), a Hugging Face cache folder, or a .gguf file."
        if usesModelPath {
            panel.directoryURL = URL(fileURLWithPath: (prefs.taskLLMModelPath as NSString).expandingTildeInPath)
                .deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keep a working path rather than swap in something that can't write summaries.
        if let problem = LocalModelPath.problem(with: url.path) {
            let alert = NSAlert()
            alert.messageText = "Ambient can't use this model"
            alert.informativeText = problem
            alert.runModal()
            return
        }
        prefs.taskLLMModelPath = url.path
    }

    private var skillPackCaption: String {
        if TaskSkillStore.exists() {
            let pack = TaskSkillStore.load()
            return "Skill pack: \(pack.source) · \(pack.examples.count) examples (~/.ambient/task-skill.json)"
        }
        return "Skill pack: the one that comes with Ambient. `ambient task skill-bootstrap` can teach it better titles once, with your Anthropic key from the Keychain."
    }
}

/// Full-window board: wider columns, same cards, no Settings chrome.
struct BoardWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var query = ""

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
                BoardSearchField(query: $query)
                    .frame(width: 260)
                Toggle("Wallpaper cues", isOn: $prefs.wallpaperShowBoard)
                    .toggleStyle(.switch)
                    .disabled(!prefs.wallpaperEnabled)
                    .help("Soft task titles on the living wallpaper. Off by default.")
            }
            let found = TaskSearch.filter(model.tasks, query: query)
            if model.tasks.isEmpty {
                Text("No tasks yet — they appear as your agents work.")
                    .font(Theme.Fonts.row)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if found.isEmpty {
                BoardNoMatches(query: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        ForEach(TaskBoardColumn.columns(found)) { column in
                            BoardColumn(column: column,
                                        sessions: model.sessions,
                                        notes: model.taskNotes,
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

/// Filters the board by title, summary, project, folder, agent or machine.
private struct BoardSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search tasks", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.row)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 6)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Theme.Colors.hairline.opacity(0.6), lineWidth: 0.5)
        )
    }
}

private struct BoardNoMatches: View {
    let query: String

    var body: some View {
        Text("No tasks match “\(query.trimmingCharacters(in: .whitespaces))”")
            .font(Theme.Fonts.row)
            .foregroundStyle(.secondary)
            .padding(.vertical, Theme.Space.sm)
    }
}

private struct BoardColumn: View {
    let column: TaskBoardColumn
    let sessions: [Session]
    /// What a card says for a moment after it's clicked, by task id.
    var notes: [String: String] = [:]
    let open: (String) -> Void
    /// Opens the Task Board window, for a column that shows only its latest cards.
    var more: (() -> Void)? = nil
    var wide: Bool = false

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(column.status.displayName)
                    .font(Theme.Fonts.sectionHeader)
                Spacer(minLength: 0)
                Text(column.total.formatted())
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.xxs)

            // Lazy: a long-lived board holds thousands of tasks, and only the ones on screen should cost anything.
            LazyVStack(spacing: Theme.Space.xs) {
                ForEach(column.tasks) { task in
                    let session = linkedSession(task)
                    // Equatable, so an agent event redraws only the cards it changed.
                    BoardCard(task: task, session: session, clock: session.flatMap { Describe.clock($0, now: now) },
                              note: notes[task.id], open: { open(task.id) })
                        .equatable()
                }
            }
            if column.total > column.tasks.count {
                moreLink(column.total - column.tasks.count)
            }
        }
        .frame(width: wide ? 260 : 220, alignment: .topLeading)
    }

    @ViewBuilder private func moreLink(_ hidden: Int) -> some View {
        let label = Text("\(hidden.formatted()) more in the Task Board")
            .font(Theme.Fonts.caption)
            .foregroundStyle(.secondary)
        if let more {
            Button(action: more) { label }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Space.xxs)
                .help("Open the Task Board window")
        } else {
            label.padding(.horizontal, Theme.Space.xxs)
        }
    }

    private func linkedSession(_ task: AgentTask) -> Session? {
        if let id = task.lastSessionId, let s = sessions.first(where: { $0.id == id }) { return s }
        return sessions.first { task.sessionIds.contains($0.id) }
    }
}

/// Equal when what it shows is: SwiftUI can't compare `open`, so without this every card on screen redraws on every
/// agent event.
private struct BoardCard: View, Equatable {
    let task: AgentTask
    let session: Session?
    /// How long the session has been at it, as of the column's last update.
    let clock: String?
    /// Where its chat is opening, or why it couldn't, for a moment after a click.
    let note: String?
    let open: () -> Void

    static func == (a: BoardCard, b: BoardCard) -> Bool {
        a.task == b.task && a.session == b.session && a.clock == b.clock && a.note == b.note
    }

    /// A task whose session ended can still open its chat. Another machine's opens there.
    private var canOpen: Bool {
        session != nil || !task.sessionIds.isEmpty || task.lastChat != nil
    }

    private var helpText: String {
        if let machine = task.machine { return canOpen ? "Opens on \(machine.label)" : "No chat to open on \(machine.label)" }
        if let session { return "Open \(session.agentLabel)" }
        return canOpen ? "Open the chat" : "No chat to open"
    }

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
                if let note {
                    Text(note)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
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
                    if let machine = task.machine {
                        Label { Text(verbatim: machine.label) } icon: { Image(systemName: "network") }
                            .labelStyle(.titleAndIcon)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let clock {
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
                            .help(Describe.remoteState(session) ?? Describe.mood(session.mood))
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
        .disabled(!canOpen)
        .help(helpText)
    }
}
