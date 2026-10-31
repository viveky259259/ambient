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
    /// Paired machines and how their links are doing, sorted by name.
    @Published private(set) var remoteLinks: [RemoteLinkStatus] = []
    /// Every applied event and sweep result, for surfaces that react to changes.
    let transitions = PassthroughSubject<SessionChange, Never>()

    let prefs: Preferences
    let snapshot = Snapshot()
    private let focuser = Focuser()
    private let store = SessionStore()
    private let taskStore = TaskStore()
    private let memoryStore = MemoryStore()
    private let stateURL: URL?
    private let dayURL: URL?
    private let tasksURL: URL?
    private let memoryURL: URL?
    private let memoryBlobs: MemoryBlobStore?
    private var daySaveWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var taskSaveWork: DispatchWorkItem?
    private var memorySaveWork: DispatchWorkItem?
    private var nextMemoryCollect = Date.distantPast
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
    /// How far each machine has been applied. Saved with the sessions, in the same file.
    private var remoteCursors: [String: RemoteCursor] = [:]
    private var unreachableWork: [String: DispatchWorkItem] = [:]

    init(prefs: Preferences, stateURL: URL?, dayURL: URL? = nil, tasksURL: URL? = nil, memoryURL: URL? = nil,
         memoryBlobs: MemoryBlobStore? = nil, titles: SessionTitles? = nil) {
        self.prefs = prefs
        self.stateURL = stateURL
        self.dayURL = dayURL
        self.tasksURL = tasksURL
        self.memoryURL = memoryURL
        self.memoryBlobs = memoryBlobs
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
            remoteCursors = StateFile.loadCursors(from: stateURL)
            store.sweep(now: Date())
            publish(save: false)
            for s in store.sessions {
                _ = taskStore.observe(SessionChange(session: s, previous: nil, event: .sessionStarted, removed: false))
            }
            publishTasks(save: false)
        }
        if let memoryURL {
            if let saved = MemoryFile.load(from: memoryURL) {
                memoryStore.load(saved)
            } else {
                // A file this version can't read: its shared files aren't abandoned, and MemoryFile.save leaves it
                // alone, so what's shared until then lasts until Ambient quits.
                nextMemoryCollect = .distantFuture
            }
            if !memoryStore.sweep().isEmpty { scheduleMemorySave() }
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
        endSessionMemory(t)
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

    // MARK: - Remote machines

    func remoteCursor(_ machine: String) -> RemoteCursor {
        remoteCursors[machine] ?? RemoteCursor()
    }

    /// Events from a machine's link. Remote input arrives only here, already through `RemoteIngest`. Returns how many
    /// were turned away because the machine has as many sessions as it can have.
    @discardableResult
    func applyRemote(_ batch: [RemoteDelivery], cursor: RemoteCursor, from machine: MachineRef) -> Int {
        // Already queued when the machine was unpaired: the allowlist wins.
        guard remoteLinks.contains(where: { $0.machine.id == machine.id }) else { return 0 }
        let (changes, saveFirst, refused) = store.apply(batch, from: machine, saved: remoteCursor(machine.id), cursor: cursor)
        remoteCursors[machine.id] = cursor
        if let i = remoteLinks.firstIndex(where: { $0.machine.id == machine.id }) {
            remoteLinks[i].lastEventAt = Date()
        }
        // Anything about to be announced reaches the disk first, with its cursor: see `SessionStore.apply(_:from:)`.
        if saveFirst, let stateURL {
            saveWork?.cancel()
            try? StateFile.save(savedSessions(store.sessions), cursors: remoteCursors, to: stateURL)
        }
        publish(save: !saveFirst)
        for t in changes {
            transitions.send(t)
            record(t)
            observeTask(t, publish: false)
        }
        // Once per batch: a board's worth of sorting per event is what a burst would otherwise cost the main thread.
        if !changes.isEmpty { publishTasks() }
        return refused
    }

    func setRemoteHealth(_ health: RemoteHealth, machine: Machine, hello: RemoteHello?, updateAvailable: Bool) {
        guard var status = remoteLinks.first(where: { $0.machine.id == machine.id }) else { return }
        status.health = health
        if let hello {
            status.shim = hello.shim
            status.level = hello.level
            status.updateAvailable = updateAvailable
        }
        setRemoteStatus(status)

        switch health {
        case .connected:
            cancelUnreachable(machine.id)
            markUnreachable(false, machine: machine.id)
        case .connecting, .stopped:
            break
        case .reconnecting:
            // A blip that heals on its own shouldn't blank a machine's sessions. Every retry reports here, so a
            // pending countdown is left running: restarting it would put off "unknown" for as long as the outage.
            guard unreachableWork[machine.id] == nil else { break }
            let work = DispatchWorkItem { [weak self] in self?.markUnreachable(true, machine: machine.id) }
            unreachableWork[machine.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        case .signInNeeded, .revoked, .upgradeNeeded:
            cancelUnreachable(machine.id)
            markUnreachable(true, machine: machine.id)
        }
    }

    private func cancelUnreachable(_ machine: String) {
        unreachableWork[machine]?.cancel()
        unreachableWork[machine] = nil
    }

    private func setRemoteStatus(_ status: RemoteLinkStatus) {
        var next = remoteLinks.filter { $0.machine.id != status.machine.id }
        next.append(status)
        remoteLinks = next.sorted { $0.machine.id < $1.machine.id }
    }

    private func markUnreachable(_ unreachable: Bool, machine: String) {
        let changes = store.setUnreachable(unreachable, machine: machine)
        guard !changes.isEmpty else { return }
        publish()
        for change in changes {
            transitions.send(change)
            observeTask(change)
        }
    }

    /// `machines` is the allowlist: anything from a machine that's no longer on it goes.
    func keepMachines(_ machines: [Machine]) {
        let paired = Set(machines.map(\.id))
        let known = Set(store.sessions.compactMap(\.origin?.machine.id)).union(remoteCursors.keys).union(remoteLinks.map(\.machine.id))
        for id in known where !paired.contains(id) {
            cancelUnreachable(id)
            remoteCursors[id] = nil
            for change in store.remove(machine: id) {
                transitions.send(change)
                observeTask(change)
            }
        }
        remoteLinks = remoteLinks.filter { paired.contains($0.machine.id) }.map { status in
            var status = status
            if let machine = machines.first(where: { $0.id == status.machine.id }) {
                status = RemoteLinkStatus(machine: machine, health: status.health, shim: status.shim, level: status.level,
                                          lastEventAt: status.lastEventAt, updateAvailable: status.updateAvailable)
            }
            return status
        }
        for machine in machines where !remoteLinks.contains(where: { $0.machine.id == machine.id }) {
            setRemoteStatus(RemoteLinkStatus(machine: machine))
        }
        publish()
    }

    /// Deletes everything a machine left in memory. `RemotePurge` handles the files.
    func purge(machine id: String) {
        for change in store.remove(machine: id) { transitions.send(change) }
        remoteCursors[id] = nil
        if taskStore.remove(machine: id) { publishTasks() }
        var next = day
        next.removeMoments(machine: id)
        if next != day {
            day = next
            scheduleDaySave()
        }
        publish()
    }

    /// Takes the user to the session — its chat, tab or window — and marks its result as seen.
    func open(_ session: Session) {
        // There's nothing local to bring forward for a remote session; opening it marks it seen.
        if session.origin == nil { focuser.focus(session) }
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

    /// Answers `ambient memory` and the memory tools of `ambient mcp`.
    func memory(_ request: MemoryRequest) -> MemoryReply {
        let revision = memoryStore.revision
        let reply = memoryStore.answer(request, sessions: store.sessions, blobs: memoryBlobs)
        if memoryStore.revision != revision { scheduleMemorySave() }
        return reply
    }

    /// Drops what a session kept only for itself when it says it ended. One the island drops for going quiet isn't
    /// over, so this isn't called for those: `MemoryStore.sweep` watches for its agent exiting.
    private func endSessionMemory(_ change: SessionChange) {
        guard change.removed, !memoryStore.sessionEnded(change.session.id).isEmpty else { return }
        scheduleMemorySave()
    }

    func setQuiet(for duration: TimeInterval?) {
        prefs.quietUntil = duration.map { Date().addingTimeInterval($0) }
        objectWillChange.send()
    }

    private func observeTask(_ change: SessionChange, publish: Bool = true) {
        let task = taskStore.observe(change)
        if publish { publishTasks() }
        if let task { scheduleSummary(for: task, session: change.session) }
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
        // Remote text goes to the local LLM only by a separate opt-in, and only ever to loopback.
        if session.isRemote {
            guard let url = config.mcpEndpoint,
                  RemoteEgress.allows(session, to: .localLLM(url), remoteSummaries: prefs.remoteSummaries) else { return }
        }
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
                defer {
                    model.summarizingTaskIDs.remove(taskID)
                    // Failures count too: a model that can't run mustn't reload on every session event.
                    model.lastSummarizedAt[taskID] = Date()
                }
                // Settings changed while this ran (another model, or summaries off): its answer and status no longer count.
                func stale() -> Bool { model.prefs.taskLLMConfig != config }
                do {
                    let resolution = await summarizer.resolve()
                    guard case let .ready(route) = resolution else {
                        if !stale() { model.taskLLMStatus = resolution.status }
                        return
                    }
                    let semantics = try await summarizer.summarize(context: context, via: route)
                    if stale() { return }
                    // Re-read the live linked session so a stale captured `.waiting` cannot re-block
                    // after the user has already unblocked.
                    let live = model.sessions.first { $0.id == session.id }
                    _ = model.taskStore.applySemantics(semantics, toTaskID: taskID, session: live)
                    model.publishTasks()
                    model.taskLLMStatus = .ready
                } catch {
                    if !stale() { model.taskLLMStatus = .failed(error.localizedDescription) }
                }
            }
        }
    }

    private func userActivated(_ app: NSRunningApplication) {
        let ids = store.sessions.filter { s in
            guard s.origin == nil, let host = s.host else { return false }
            return host.bundleId == app.bundleIdentifier || host.pids.contains(app.processIdentifier)
        }.map(\.id)
        for id in ids { acknowledge(id) }
    }

    private func sweep() {
        refreshTitles()
        rollOverDay()
        if !memoryStore.sweep().isEmpty { scheduleMemorySave() }
        collectMemoryBlobs()
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
            !$0.isRemote && !$0.sessionId.hasPrefix("demo-") && now.timeIntervalSince(titleCheckedAt[$0.id] ?? .distantPast) >= 60
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
        let sessions = savedSessions(self.sessions)
        let cursors = remoteCursors
        let work = DispatchWorkItem { try? StateFile.save(sessions, cursors: cursors, to: stateURL) }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func savedSessions(_ sessions: [Session]) -> [Session] {
        sessions.filter { !$0.sessionId.hasPrefix("demo-") }
    }

    private func scheduleTaskSave() {
        guard let tasksURL else { return }
        taskSaveWork?.cancel()
        let tasks = self.tasks
        let work = DispatchWorkItem { try? TaskFile.save(tasks, to: tasksURL) }
        taskSaveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Saves shared memory shortly after it settles.
    private func scheduleMemorySave() {
        guard let memoryURL else { return }
        memorySaveWork?.cancel()
        let entries = memoryStore.entries
        let work = DispatchWorkItem { try? MemoryFile.save(entries, to: memoryURL) }
        memorySaveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Every few minutes, deletes shared files nothing refers to any more. On a timer, not after saves: a copy
    /// forgotten while it's still within the grace period would otherwise wait for the next change.
    private func collectMemoryBlobs() {
        let now = Date(), grace: TimeInterval = 300
        guard let memoryBlobs, now >= nextMemoryCollect else { return }
        nextMemoryCollect = now.addingTimeInterval(grace)
        let keep = memoryStore.blobs
        DispatchQueue.global(qos: .utility).async {
            memoryBlobs.collect(keeping: keep, changedBefore: now.addingTimeInterval(-grace))
        }
    }

    /// Saves immediately, e.g. when quitting.
    func saveNow() {
        daySaveWork?.cancel()
        if let dayURL { try? DayLogFile.save(day, to: dayURL) }
        saveWork?.cancel()
        if let stateURL {
            try? StateFile.save(savedSessions(sessions), cursors: remoteCursors, to: stateURL)
        }
        taskSaveWork?.cancel()
        if let tasksURL { try? TaskFile.save(tasks, to: tasksURL) }
        memorySaveWork?.cancel()
        if let memoryURL { try? MemoryFile.save(memoryStore.entries, to: memoryURL) }
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
