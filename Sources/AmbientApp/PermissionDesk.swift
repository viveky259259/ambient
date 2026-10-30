import AmbientCore
import AppKit
import Combine

/// Permission prompts the island can answer, when the user has turned that on in Settings › Island. Each
/// asking hook holds a socket thread until the user answers, its time is up, or the agent moves on; only a
/// click answers, and everything else hands the prompt back to the agent with `ask`.
final class PermissionDesk: ObservableObject {
    /// The prompt on the island, and how many are waiting in all.
    @Published private(set) var current: PermissionQueue.Entry?
    @Published private(set) var count = 0

    private let prefs: Preferences
    private var queue = PermissionQueue()
    private var waiters: [String: Waiter] = [:]
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    init(model: AppModel, prefs: Preferences) {
        self.prefs = prefs
        cancellable = model.transitions.sink { [weak self] t in self?.agentMoved(t) }
    }

    /// Called on a socket thread: blocks until the prompt is settled.
    func answer(for ask: PermissionAsk) -> PermissionAnswer {
        let waiter = Waiter()
        DispatchQueue.main.async { self.enqueue(ask, waiter: waiter) }
        // The main thread settles every prompt by its deadline; this bound only guards against it never doing so.
        return waiter.wait(seconds: (PermissionSettings.waits.last ?? 60) + 2)
    }

    /// The user's click. Returns the prompt it settled, if it was still waiting.
    @discardableResult
    func settle(_ id: String, with answer: PermissionAnswer) -> PermissionAsk? {
        guard let ask = queue.remove(id) else { return nil }
        waiters.removeValue(forKey: id)?.resolve(answer)
        publish()
        return ask
    }

    private func enqueue(_ ask: PermissionAsk, waiter: Waiter) {
        // Hand it straight back when the island can't show it, or when the user is already in the agent's app
        // and would rather answer there.
        guard prefs.answerPermissions, prefs.islandEnabled, !HostActivator.isFrontmost(ask.event.host),
              queue.add(ask, now: Date(), wait: TimeInterval(prefs.permissionWait)) else {
            waiter.resolve(.ask)
            return
        }
        waiters[ask.id] = waiter
        publish()
    }

    private func agentMoved(_ t: SessionChange) {
        guard !queue.entries.isEmpty else { return }
        let s = t.session
        let gone = t.removed
            ? queue.entries.map(\.ask).filter { $0.event.agent == s.agent && $0.event.sessionId == s.sessionId }
            : t.event.map { queue.withdraw(after: AgentEvent(agent: s.agent, sessionId: s.sessionId, cwd: nil, kind: $0,
                                                             timestamp: s.lastEventAt)) } ?? []
        for ask in gone {
            queue.remove(ask.id)
            waiters.removeValue(forKey: ask.id)?.resolve(.ask)
        }
        if !gone.isEmpty { publish() }
    }

    private func expire() {
        for ask in queue.expire(now: Date()) { waiters.removeValue(forKey: ask.id)?.resolve(.ask) }
        publish()
    }

    private func publish() {
        if current != queue.current { current = queue.current }
        if count != queue.entries.count { count = queue.entries.count }
        if queue.entries.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.expire() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// One asking hook's answer, handed from the main thread to the socket thread that waits for it.
    private final class Waiter: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var answer: PermissionAnswer?

        func resolve(_ answer: PermissionAnswer) {
            lock.lock()
            let first = self.answer == nil
            if first { self.answer = answer }
            lock.unlock()
            if first { done.signal() }
        }

        func wait(seconds: Int) -> PermissionAnswer {
            _ = done.wait(timeout: .now() + .seconds(seconds))
            lock.lock(); defer { lock.unlock() }
            return answer ?? .ask
        }
    }
}
