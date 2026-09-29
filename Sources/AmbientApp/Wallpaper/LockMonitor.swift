import AppKit
import Combine

/// Whether the screen is locked. A lock counts once it has held for two seconds, because Ctrl-Cmd-Q briefly
/// reports lock → unlock → lock. An unlock counts at once, so nothing lingers over the desktop.
final class LockMonitor {
    @Published private(set) var isLocked: Bool
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private static let settle: TimeInterval = 2

    init() { isLocked = Self.screenIsLocked() }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.lockReported()
            },
            center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.unlockReported()
            },
        ]
    }

    private func lockReported() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isLocked else { return }
            self.isLocked = true
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    private func unlockReported() {
        pending?.cancel()
        pending = nil
        if isLocked { isLocked = false }
    }

    static func screenIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
