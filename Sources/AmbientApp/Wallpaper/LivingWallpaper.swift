import AmbientCore
import AppKit
import Combine
import os

/// Runs the living wallpaper: builds what the scene shows and decides where it's drawn. At the desk, a layer of
/// windows; on the lock screen, windows in a SkyLight space above it.
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

    let feed = SceneFeed()

    private let model: AppModel
    private let prefs: Preferences
    private let desktop: DesktopLayer
    private let lockMonitor = LockMonitor()
    private var lockLayer: LockLayer?
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var minuteTimer: Timer?
    private var slots: [String: Int] = [:]
    private var screensAsleep = false
    private var locked = false

    /// The macOS build the live lock screen failed on; the fallback is used until the build changes.
    private static let fallbackBuildKey = "wallpaperLockFallbackBuild"
    /// Debug: `defaults write com.viveky259259.Ambient AmbientForceWallpaperSwap -bool true` skips the live layer.
    private static let forceSwapKey = "AmbientForceWallpaperSwap"
    private static var osBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    init(model: AppModel, prefs: Preferences, paths: AmbientPaths) {
        self.model = model
        self.prefs = prefs
        desktop = DesktopLayer(feed: feed)
        desktop.onVisibilityChange = { [weak self] in self?.updateMotion() }
    }

    func start() {
        model.$sessions.combineLatest(model.$day)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        // objectWillChange fires before the new value lands; hopping to the next turn of the run loop reads it.
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
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
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   keeping: slots)
        slots = Dictionary(uniqueKeysWithValues: desk.inhabitants.map { ($0.id, $0.slot) })
        feed.desk = desk
        feed.lock = prefs.wallpaperOnLockScreen
            ? SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .lock,
                              lockMessages: prefs.wallpaperLockMessages, keeping: slots)
            : nil
        if !desktop.isInstalled { desktop.install() }
        updateLockMode()
        updateMotion()
    }

    private func turnOff() {
        desktop.uninstall()
        lockLayer?.uninstall()
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
        } else {
            mode = liveLockAvailable ? .live : .unavailable
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
        guard liveLockAvailable, let skyLight = SkyLight.shared else { return }
        if lockLayer == nil { lockLayer = LockLayer(feed: feed, skyLight: skyLight) }
        guard let lockLayer, lockLayer.isInstalled || lockLayer.install() else {
            return fallBack(because: "SkyLight refused a space")
        }
        lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
    }

    private func leaveLock() {
        lockLayer?.hide()
    }

    /// The live layer can't show here: remember that for this macOS build.
    private func fallBack(because reason: String) {
        log.notice("Live lock screen unavailable (\(reason, privacy: .public)) on \(Self.osBuild, privacy: .public)")
        UserDefaults.standard.set(Self.osBuild, forKey: Self.fallbackBuildKey)
        lockLayer?.uninstall()
        lockLayer = nil
        updateLockMode()
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
