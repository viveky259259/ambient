import AmbientCore
import AppKit
import Combine
import os

/// Runs the living wallpaper: builds what the scene shows and decides where it's drawn. At the desk, a layer of
/// windows; on the lock screen, the SkyLight layer, or, where that can't show, the real wallpaper swapped while locked.
final class LivingWallpaper: ObservableObject {
    enum LockMode: Equatable {
        /// The feature or the lock-screen option is off.
        case off
        /// Drawn live above the lock screen.
        case live
        /// Set as the real wallpaper while locked, and put back on unlock.
        case swap
        /// Neither works on this Mac.
        case unavailable
    }

    @Published private(set) var lockMode: LockMode = .off
    /// A swapped wallpaper hasn't been put back yet.
    @Published private(set) var restorePending = false

    let feed = SceneFeed()
    let calendar = CalendarSource()

    private let model: AppModel
    private let prefs: Preferences
    private let desktop: DesktopLayer
    private let lockMonitor = LockMonitor()
    private var lockLayer: LockLayer?
    private let swap: WallpaperSwap
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var minuteTimer: Timer?
    private var swapTimer: Timer?
    private var slots: [String: Int] = [:]
    private var screensAsleep = false
    private var locked = false
    private var swapping = false
    private var restoring = false
    private var lastSwap = Date.distantPast
    private var lastSwapMoods: [Mood] = []

    /// The macOS build the live lock screen failed on; the fallback is used until the build changes.
    private static let fallbackBuildKey = "wallpaperLockFallbackBuild"
    /// Debug: `defaults write com.viveky259259.Ambient AmbientForceWallpaperSwap -bool true` uses the fallback.
    private static let forceSwapKey = "AmbientForceWallpaperSwap"
    private static var osBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    init(model: AppModel, prefs: Preferences, paths: AmbientPaths) {
        self.model = model
        self.prefs = prefs
        desktop = DesktopLayer(feed: feed)
        swap = WallpaperSwap(paths: paths)
        desktop.onVisibilityChange = { [weak self] in self?.updateMotion() }
    }

    func start() {
        // A swap left behind by a crash or a forced quit is put right first.
        if swap.restorePending {
            restorePending = true
            if !LockMonitor.screenIsLocked() { restoreWallpaper() }
        }

        model.$sessions.combineLatest(model.$day)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        // objectWillChange fires before the new value lands; hopping to the next turn of the run loop reads it.
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        calendar.$next
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        locked = lockMonitor.isLocked
        lockMonitor.$isLocked
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lockChanged($0) }
            .store(in: &cancellables)
        lockMonitor.start()

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensChanged()
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
            center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
                self?.updateMotion()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
        ]
        scheduleMinuteTick()
        refresh()
    }

    // MARK: - What the scene shows

    /// Rebuilds the scene: on every change, and at the top of every minute for the clock and the light.
    func refresh() {
        guard prefs.wallpaperEnabled else { return turnOff() }
        let now = Date()
        let kind = ScenePolicy.kind(for: prefs.sceneChoice, on: now)
        if prefs.wallpaperCalendar { calendar.start() } else { calendar.stop() }
        let next = prefs.wallpaperCalendar ? calendar.next : nil
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   nextEvent: next, keeping: slots)
        slots = Dictionary(uniqueKeysWithValues: desk.inhabitants.map { ($0.id, $0.slot) })
        feed.desk = desk
        feed.lock = prefs.wallpaperOnLockScreen
            ? SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .lock,
                              lockMessages: prefs.wallpaperLockMessages, nextEvent: next, keeping: slots)
            : nil
        if !desktop.isInstalled { desktop.install() }
        updateLockMode()
        updateMotion()
        swapIfMoodsChanged()
    }

    private func turnOff() {
        desktop.uninstall()
        lockLayer?.uninstall()
        calendar.stop()
        if swapping { stopSwap() }
        if feed.desk != nil { feed.desk = nil }
        if feed.lock != nil { feed.lock = nil }
        if lockMode != .off { lockMode = .off }
    }

    // MARK: - Lock screen

    private var liveLockAvailable: Bool {
        !UserDefaults.standard.bool(forKey: Self.forceSwapKey) && SkyLight.shared != nil
            && UserDefaults.standard.string(forKey: Self.fallbackBuildKey) != Self.osBuild
    }

    private func updateLockMode() {
        let mode: LockMode
        if !prefs.wallpaperEnabled || !prefs.wallpaperOnLockScreen {
            mode = .off
        } else if liveLockAvailable {
            mode = .live
        } else {
            mode = swap.isSupported ? .swap : .unavailable
        }
        if mode != lockMode { lockMode = mode }
    }

    private func lockChanged(_ isLocked: Bool) {
        locked = isLocked
        updateMotion()
        if isLocked { enterLock() } else { leaveLock() }
    }

    private func enterLock() {
        guard prefs.wallpaperEnabled, prefs.wallpaperOnLockScreen else { return }
        guard liveLockAvailable, let skyLight = SkyLight.shared else { return startSwap() }
        if lockLayer == nil { lockLayer = LockLayer(feed: feed, skyLight: skyLight) }
        guard let lockLayer, lockLayer.isInstalled || lockLayer.install() else {
            return fallBack(because: "SkyLight refused a space")
        }
        lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
    }

    private func leaveLock() {
        lockLayer?.hide()
        if swapping {
            stopSwap()
        } else if swap.restorePending {
            restoreWallpaper()   // Retry a restore that failed earlier.
        }
    }

    /// The live layer can't show here: remember that for this macOS build and swap the wallpaper instead.
    private func fallBack(because reason: String) {
        log.notice("Live lock screen unavailable (\(reason, privacy: .public)) on \(Self.osBuild, privacy: .public); using the wallpaper swap")
        UserDefaults.standard.set(Self.osBuild, forKey: Self.fallbackBuildKey)
        lockLayer?.uninstall()
        lockLayer = nil
        updateLockMode()
        if locked { startSwap() }
    }

    // MARK: - Wallpaper swap (fallback)

    private func startSwap() {
        guard !swapping else { return }
        guard swap.begin() else {
            if lockMode != .unavailable { lockMode = .unavailable }
            return
        }
        swapping = true
        restorePending = true
        renderSwap()
        swapTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.renderSwap() }
    }

    private func renderSwap() {
        guard swapping, let state = feed.lock else { return }
        lastSwap = Date()
        lastSwapMoods = state.inhabitants.map(\.mood)
        MainActor.assumeIsolated {
            let main = NSScreen.screens.first
            let images: [(screen: NSScreen, png: Data)] = NSScreen.screens.compactMap { screen in
                let isMain = screen == main
                guard let png = WallpaperSwap.render(isMain ? state : state.scenery(), for: screen, showsText: isMain)
                else { return nil }
                return (screen: screen, png: png)
            }
            swap.show(images)
        }
    }

    /// While swapped, a change in anyone's mood redraws the wallpaper, at most every 8 seconds.
    private func swapIfMoodsChanged() {
        guard swapping, let state = feed.lock, state.inhabitants.map(\.mood) != lastSwapMoods,
              Date().timeIntervalSince(lastSwap) >= 8 else { return }
        renderSwap()
    }

    private func stopSwap() {
        swapTimer?.invalidate()
        swapTimer = nil
        swapping = false
        restoreWallpaper()
    }

    /// Puts the user's own wallpaper back. Also Settings' "Restore my wallpaper".
    func restoreWallpaper() {
        guard !restoring else { return }
        restoring = true
        swap.restore { [weak self] ok in
            guard let self else { return }
            self.restoring = false
            self.restorePending = !ok
            if !ok { self.log.error("Couldn't restore the wallpaper; Settings offers to try again") }
        }
    }

    // MARK: - Motion, displays and time

    private func updateMotion() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let desk = desktop.isVisible && !screensAsleep && !lowPower && !locked
        let lock = locked && !screensAsleep && !lowPower
        if feed.reduceMotion != reduce { feed.reduceMotion = reduce }
        if feed.deskAnimated != desk { feed.deskAnimated = desk }
        if feed.lockAnimated != lock { feed.lockAnimated = lock }
    }

    private func screensChanged() {
        guard prefs.wallpaperEnabled else { return }
        desktop.install()
        if let lockLayer, lockLayer.isInstalled {
            lockLayer.install()   // starts hidden
            if locked, lockMode == .live {
                lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
            }
        }
        if swapping { renderSwap() }
        updateMotion()
    }

    private func clockChanged() {
        scheduleMinuteTick()
        refresh()
    }

    private func scheduleMinuteTick() {
        minuteTimer?.invalidate()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }
}
