import AmbientCore
import AppKit
import Combine

/// The app's source of truth: sessions folded from agent events, published on the main thread.
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var mood: Mood = .idle
    @Published private(set) var tasks: [AgentTask] = []
    @Published private(set) var taskLLMStatus: TaskLLMStatus = .disabled
    /// How the board's model runs, once the last probe found it usable.
    @Published private(set) var taskModelRoute: TaskModelRoute?
    /// Today's story, for the living wallpaper.
    @Published private(set) var day = DayLog(now: Date())
    /// Every applied event and sweep result, for surfaces that react to changes.
    let transitions = PassthroughSubject<SessionChange, Never>()

    let prefs: Preferences
    let snapshot = Snapshot()
    private let focuser = Focuser()
    private let store = SessionStore()
    private let taskStore = TaskStore()
    private let stateURL: URL?
    private let dayURL: URL?
    private let tasksURL: URL?
    private var daySaveWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var taskSaveWork: DispatchWorkItem?
    private var sweepTimer: Timer?
    private var llmProbeTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let titles: SessionTitles?
    private let titleQueue = DispatchQueue(label: "com.viveky259259.Ambient.titles", qos: .utility)
    private let llmQueue = DispatchQueue(label: "com.viveky259259.Ambient.taskllm", qos: .utility)
    private var titleCheckedAt: [String: Date] = [:]
    private var lastSummarizedAt: [String: Date] = [:]
    private var summarizingTaskIDs = Set<String>()
    private var llmProbeGeneration = 0

    init(prefs: Preferences, stateURL: URL?, dayURL: URL? = nil, tasksURL: URL? = nil, titles: SessionTitles? = nil) {
        self.prefs = prefs
        self.stateURL = stateURL
        self.dayURL = dayURL
        self.tasksURL = tasksURL
        self.titles = titles
    }

    func start() {
        if let dayURL, let saved = DayLogFile.load(from: dayURL) { day = saved }
        rollOverDay()
        if let tasksURL {
            taskStore.load(TaskFile.load(from: tasksURL))
            publishTasks(save: false)
        }
        if let stateURL {
            store.load(StateFile.load(from: stateURL))
            store.sweep(now: Date())
            publish(save: false)
            for s in store.sessions {
                _ = taskStore.observe(SessionChange(session: s, previous: nil, event: .sessionStarted, removed: false))
            }
            publishTasks(save: false)
        }
        refreshTitles()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sweep() }
        sweepTimer?.tolerance = 1
        llmProbeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshTaskLLMStatus()
        }
        llmProbeTimer?.tolerance = 5
        refreshTaskLLMStatus()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.userActivated(app)
        })
    }

    func apply(_ event: AgentEvent) {
        guard let t = store.apply(event) else { return }
        publish()
        transitions.send(t)
        record(t)
        observeTask(t)
        refreshTitles()
        if AlertPolicy.attentionMoods.contains(t.session.mood), t.session.mood != t.previousMood,
           HostActivator.isFrontmost(t.session.host) {
            // The user is already in the app: let the result or prompt register, then consider it seen.
            let id = t.session.id, activity = t.session.activity
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, let s = self.store.session(id: id), s.activity == activity,
                      HostActivator.isFrontmost(s.host) else { return }
                self.acknowledge(id)
            }
        }
    }

    /// Takes the user to the session — its chat, tab or window — and marks its result as seen.
    func open(_ session: Session) {
        focuser.focus(session)
        acknowledge(session.id)
    }

    /// Opens the most urgent linked session for a board task.
    @discardableResult
    func openTask(_ id: String) -> Session? {
        guard let task = taskStore.task(id: id) else { return nil }
        let linked = task.sessionIds.compactMap { store.session(id: $0) }
        let match = SessionMatcher.find(nil, in: linked.isEmpty ? store.sessions.filter { task.sessionIds.contains($0.id) } : linked)
            ?? linked.first
            ?? task.lastSessionId.flatMap { store.session(id: $0) }
        guard let match else { return nil }
        open(match)
        return match
    }

    func acknowledge(_ id: String) {
        guard store.acknowledge(sessionID: id), let s = store.session(id: id) else { return }
        publish()
        let change = SessionChange(session: s, previous: s.activity, event: nil, removed: false)
        transitions.send(change)
        observeTask(change)
    }

    func acknowledgeAll() {
        for s in store.sessions { acknowledge(s.id) }
    }

    func upsertTask(_ draft: AgentTask) -> AgentTask {
        let saved = taskStore.upsert(draft)
        publishTasks()
        return saved
    }

    func setQuiet(for duration: TimeInterval?) {
        prefs.quietUntil = duration.map { Date().addingTimeInterval($0) }
        objectWillChange.send()
    }

    private func observeTask(_ change: SessionChange) {
        guard let task = taskStore.observe(change) else {
            publishTasks()
            return
        }
        publishTasks()
        scheduleSummary(for: task, session: change.session)
    }

    /// Re-probe local-agent MCP / Models volume / the model path's runtime. Safe to call from Settings.
    func refreshTaskLLMStatus() {
        let config = prefs.taskLLMConfig
        llmProbeGeneration += 1
        guard config.enabled else {
            taskLLMStatus = .disabled
            taskModelRoute = nil
            return
        }
        let generation = llmProbeGeneration
        let summarizer = TaskSummarizer(config: config)
        Task { @MainActor [weak self] in
            let resolution = await summarizer.resolve()
            // A slower probe of settings that have since changed doesn't get the last word.
            guard let self, self.llmProbeGeneration == generation else { return }
            self.taskLLMStatus = resolution.status
            self.taskModelRoute = resolution.route
        }
    }

    /// Applies a change from `ambient task model` / `ambient mcp` and returns the settings that result.
    func setTaskModel(_ change: TaskModelChange) -> TaskLLMConfig {
        if let path = change.modelPath { prefs.taskLLMModelPath = path.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let python = change.pythonPath { prefs.taskLLMPython = python.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let enabled = change.enabled { prefs.taskLLMEnabled = enabled }
        refreshTaskLLMStatus()
        return prefs.taskLLMConfig
    }

    private func scheduleSummary(for task: AgentTask, session: Session) {
        let config = prefs.taskLLMConfig
        guard config.enabled else { return }
        if session.sessionId.hasPrefix("demo-") { return }
        let now = Date()
        if let last = lastSummarizedAt[task.id], now.timeIntervalSince(last) < config.minRefreshSeconds { return }
        if summarizingTaskIDs.contains(task.id) { return }
        summarizingTaskIDs.insert(task.id)
        taskLLMStatus = .summarizing
        let titles = self.titles
        let readTranscripts = config.readTranscripts
        let taskID = task.id
        llmQueue.async { [weak self] in
            guard let model = self else { return }
            let excerpt = readTranscripts ? titles?.excerpt(for: session) : nil
            let context = SessionContextBuilder.make(session: session, transcriptExcerpt: excerpt)
            let summarizer = TaskSummarizer(config: config)
            Task { @MainActor in
                defer { model.summarizingTaskIDs.remove(taskID) }
                do {
                    let resolution = await summarizer.resolve()
                    guard case let .ready(route) = resolution else {
                        model.taskLLMStatus = resolution.status
                        return
                    }
                    let semantics = try await summarizer.summarize(context: context, via: route)
                    // Re-read the live linked session so a stale captured `.waiting` cannot re-block
                    // after the user has already unblocked.
                    let live = model.sessions.first { $0.id == session.id }
                    _ = model.taskStore.applySemantics(semantics, toTaskID: taskID, session: live)
                    model.lastSummarizedAt[taskID] = Date()
                    model.publishTasks()
                    model.taskLLMStatus = .ready
                } catch {
                    model.taskLLMStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func userActivated(_ app: NSRunningApplication) {
        let ids = store.sessions.filter { s in
            guard let host = s.host else { return false }
            return host.bundleId == app.bundleIdentifier || host.pids.contains(app.processIdentifier)
        }.map(\.id)
        for id in ids { acknowledge(id) }
    }

    private func sweep() {
        refreshTitles()
        rollOverDay()
        let changes = store.sweep(now: Date())
        if prefs.quietUntil != nil, !prefs.isQuiet { prefs.quietUntil = nil }
        guard !changes.isEmpty else { return }
        publish()
        for change in changes {
            transitions.send(change)
            observeTask(change)
        }
    }

    /// Looks up the chat or thread title of each session in the background: when it first appears, then at
    /// most once a minute, since titles are generated and renamed while a session runs.
    private func refreshTitles() {
        guard let titles else { return }
        let now = Date()
        let due = store.sessions.filter {
            !$0.sessionId.hasPrefix("demo-") && now.timeIntervalSince(titleCheckedAt[$0.id] ?? .distantPast) >= 60
        }
        guard !due.isEmpty else { return }
        for s in due { titleCheckedAt[s.id] = now }
        let live = Set(store.sessions.map(\.id))
        titleCheckedAt = titleCheckedAt.filter { live.contains($0.key) }
        titleQueue.async { [weak self] in
            let found = due.compactMap { s in titles.title(for: s).map { (s.id, $0) } }
            DispatchQueue.main.async {
                guard let self else { return }
                var changed = false
                for (id, title) in found where self.store.setTitle(title, sessionID: id) { changed = true }
                if changed {
                    self.publish()
                    for s in self.store.sessions where found.contains(where: { $0.0 == s.id }) {
                        self.observeTask(SessionChange(session: s, previous: s.activity, event: nil, removed: false))
                    }
                }
            }
        }
    }

    /// Counts an applied event in today's story.
    private func record(_ t: SessionChange) {
        var next = day
        next.apply(t, now: Date())
        guard next != day else { return }
        day = next
        scheduleDaySave()
    }

    /// Starts a fresh day after midnight. Copies first: mutating a @Published value in place publishes even when nothing changes.
    private func rollOverDay() {
        var next = day
        guard next.rollOver(now: Date()) else { return }
        day = next
        scheduleDaySave()
    }

    private func scheduleDaySave() {
        guard let dayURL else { return }
        daySaveWork?.cancel()
        let log = day
        let work = DispatchWorkItem { try? DayLogFile.save(log, to: dayURL) }
        daySaveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func publish(save: Bool = true) {
        sessions = store.sessions
        mood = store.mood
        snapshot.set(sessions: sessions, mood: mood, tasks: taskStore.tasks)
        if save { scheduleSave() }
    }

    private func publishTasks(save: Bool = true) {
        tasks = taskStore.tasks
        snapshot.set(sessions: sessions, mood: mood, tasks: tasks)
        if save { scheduleTaskSave() }
    }

    /// Writes sessions to disk shortly after they settle; demo sessions aren't worth keeping.
    private func scheduleSave() {
        guard let stateURL else { return }
        saveWork?.cancel()
        let sessions = self.sessions.filter { !$0.sessionId.hasPrefix("demo-") }
        let work = DispatchWorkItem { try? StateFile.save(sessions, to: stateURL) }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func scheduleTaskSave() {
        guard let tasksURL else { return }
        taskSaveWork?.cancel()
        let tasks = self.tasks
        let work = DispatchWorkItem { try? TaskFile.save(tasks, to: tasksURL) }
        taskSaveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Saves immediately, e.g. when quitting.
    func saveNow() {
        daySaveWork?.cancel()
        if let dayURL { try? DayLogFile.save(day, to: dayURL) }
        saveWork?.cancel()
        if let stateURL {
            try? StateFile.save(sessions.filter { !$0.sessionId.hasPrefix("demo-") }, to: stateURL)
        }
        taskSaveWork?.cancel()
        if let tasksURL { try? TaskFile.save(tasks, to: tasksURL) }
    }

    /// Thread-safe copy of the state, for answering `ambient status` / `ambient tasks` off the main thread.
    final class Snapshot: @unchecked Sendable {
        private let lock = NSLock()
        private var sessions: [Session] = []
        private var mood: Mood = .idle
        private var tasks: [AgentTask] = []

        func set(sessions: [Session], mood: Mood, tasks: [AgentTask] = []) {
            lock.lock(); defer { lock.unlock() }
            self.sessions = sessions
            self.mood = mood
            self.tasks = tasks
        }

        func get() -> ([Session], Mood) {
            lock.lock(); defer { lock.unlock() }
            return (sessions, mood)
        }

        func getTasks() -> [AgentTask] {
            lock.lock(); defer { lock.unlock() }
            return tasks
        }
    }
}
