import Foundation

/// The lock-screen fallback's life cycle as a pure state machine: when to swap the wallpaper, when to draw it again,
/// and when to put the user's own back. The app performs the actions; nothing here touches files. Keeping the steps
/// in one place makes sure a swap never runs while a restore is still putting the wallpaper back.
public struct WallpaperSwapFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle, swapping, restoring
    }

    public enum Action: Equatable, Sendable {
        /// Back up the store (see `WallpaperBackup`) and mark the swap; report the result with `began(ok:now:)`.
        case begin
        /// Draw the scene and set it as the wallpaper.
        case render
        /// Put the user's wallpaper back; report with `restoreFinished(ok:now:)`. `force`: this lock set Ambient's
        /// image, so restore without first checking that it's still set. Otherwise (a leftover from a crash or a
        /// failed restore) keep a wallpaper the user has picked since.
        case restore(force: Bool)
    }

    /// Mood changes redraw the swapped wallpaper at most this often.
    public static let moodRedrawSpacing: TimeInterval = 8

    public private(set) var phase: Phase = .idle
    /// A swap happened and hasn't been undone.
    public private(set) var pending: Bool
    /// Whether the Mac is locked, as far as the fallback has been told.
    public private(set) var locked = false
    private var displaysAsleep = false
    private var lastRender = Date.distantPast

    public init(pending: Bool) {
        self.pending = pending
    }

    /// At launch: put right a swap left behind by a crash, unless the Mac is locked (then on unlock).
    public mutating func launched(locked: Bool) -> [Action] {
        self.locked = locked
        guard pending, !locked, phase == .idle else { return [] }
        phase = .restoring
        return [.restore(force: false)]
    }

    /// The lock screen needs the fallback. A lock that arrives while a restore runs waits for it.
    public mutating func lock(now: Date) -> [Action] {
        locked = true
        guard phase == .idle else { return [] }
        phase = .swapping
        return [.begin]
    }

    public mutating func began(ok: Bool, now: Date) -> [Action] {
        guard phase == .swapping else { return [] }
        guard ok else {
            phase = .idle
            return []
        }
        pending = true
        return render(now: now)
    }

    public mutating func unlock() -> [Action] {
        locked = false
        switch phase {
        case .swapping:
            phase = .restoring
            return [.restore(force: true)]
        case .restoring:
            return []
        case .idle:
            guard pending else { return [] }
            phase = .restoring
            return [.restore(force: false)]
        }
    }

    public mutating func restoreFinished(ok: Bool, now: Date) -> [Action] {
        guard phase == .restoring else { return [] }
        pending = !ok
        phase = .idle
        return locked ? lock(now: now) : []
    }

    /// Settings' "Restore my wallpaper".
    public mutating func retry() -> [Action] {
        guard phase == .idle, pending, !locked else { return [] }
        phase = .restoring
        return [.restore(force: false)]
    }

    /// The periodic redraw while swapped.
    public mutating func tick(now: Date) -> [Action] { render(now: now) }

    public mutating func moodsChanged(now: Date) -> [Action] {
        guard now.timeIntervalSince(lastRender) >= Self.moodRedrawSpacing else { return [] }
        return render(now: now)
    }

    public mutating func screensChanged(now: Date) -> [Action] { render(now: now) }

    public mutating func displaysSlept() {
        displaysAsleep = true
    }

    public mutating func displaysWoke(now: Date) -> [Action] {
        displaysAsleep = false
        return render(now: now)
    }

    private mutating func render(now: Date) -> [Action] {
        guard phase == .swapping, pending, !displaysAsleep else { return [] }
        lastRender = now
        return [.render]
    }
}

/// What to do with the wallpaper backup before a swap.
public enum WallpaperBackup {
    public enum Decision: Equatable, Sendable {
        /// The store holds the user's own wallpaper: back it up.
        case takeNew
        /// Ambient's image is set, so the existing backup is the only record of the user's wallpaper: keep it.
        case keepExisting
        /// Ambient's image is set and there's no backup to put back: don't swap.
        case refuse
    }

    public static func decide(backupPresent: Bool, storeShowsAmbient: Bool) -> Decision {
        guard storeShowsAmbient else { return .takeNew }
        return backupPresent ? .keepExisting : .refuse
    }
}

/// The live lock layer's self-check.
public enum LockLayerCheck {
    /// Fall back to the wallpaper swap only when the layer can't be seen with the displays awake: a window on a
    /// sleeping display is never visible, which says nothing about the lock screen.
    public static func shouldFallBack(windowVisible: Bool, displaysAsleep: Bool) -> Bool {
        !windowVisible && !displaysAsleep
    }
}
