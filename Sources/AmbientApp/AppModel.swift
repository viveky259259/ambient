import AmbientCore
import AppKit
import Combine

/// The app's source of truth: sessions folded from agent events, published on the main thread.
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var mood: Mood = .idle
    /// Every applied event and sweep result, for surfaces that react to changes.
    let transitions = PassthroughSubject<SessionChange, Never>()

    let prefs: Preferences
    let snapshot = Snapshot()
    private let focuser = Focuser()
    private let store = SessionStore()
    private let stateURL: URL?
    private var saveWork: DispatchWorkItem?
    private var sweepTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(prefs: Preferences, stateURL: URL?) {
        self.prefs = prefs
        self.stateURL = stateURL
    }

    func start() {
        if let stateURL {
            store.load(StateFile.load(from: stateURL))
            store.sweep(now: Date())
            publish(save: false)
        }
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sweep() }
        sweepTimer?.tolerance = 1
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

    func acknowledge(_ id: String) {
        guard store.acknowledge(sessionID: id), let s = store.session(id: id) else { return }
        publish()
        transitions.send(SessionChange(session: s, previous: s.activity, event: nil, removed: false))
    }

    func acknowledgeAll() {
        for s in store.sessions { acknowledge(s.id) }
    }

    func setQuiet(for duration: TimeInterval?) {
        prefs.quietUntil = duration.map { Date().addingTimeInterval($0) }
        objectWillChange.send()
    }

    private func userActivated(_ app: NSRunningApplication) {
        let ids = store.sessions.filter { s in
            guard let host = s.host else { return false }
            return host.bundleId == app.bundleIdentifier || host.pids.contains(app.processIdentifier)
        }.map(\.id)
        for id in ids { acknowledge(id) }
    }

    private func sweep() {
        let changes = store.sweep(now: Date())
        if prefs.quietUntil != nil, !prefs.isQuiet { prefs.quietUntil = nil }
        guard !changes.isEmpty else { return }
        publish()
        changes.forEach(transitions.send)
    }

    private func publish(save: Bool = true) {
        sessions = store.sessions
        mood = store.mood
        snapshot.set(sessions: sessions, mood: mood)
        if save { scheduleSave() }
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

    /// Saves immediately, e.g. when quitting.
    func saveNow() {
        saveWork?.cancel()
        guard let stateURL else { return }
        try? StateFile.save(sessions.filter { !$0.sessionId.hasPrefix("demo-") }, to: stateURL)
    }

    /// Thread-safe copy of the state, for answering `ambient status` off the main thread.
    final class Snapshot: @unchecked Sendable {
        private let lock = NSLock()
        private var sessions: [Session] = []
        private var mood: Mood = .idle

        func set(sessions: [Session], mood: Mood) {
            lock.lock(); defer { lock.unlock() }
            self.sessions = sessions
            self.mood = mood
        }

        func get() -> ([Session], Mood) {
            lock.lock(); defer { lock.unlock() }
            return (sessions, mood)
        }
    }
}
