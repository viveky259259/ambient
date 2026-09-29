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
    /// When to swap, redraw and restore the wallpaper; this class only carries out its actions.
    private var swapFlow: WallpaperSwapFlow
    private var lastSwapMoods: [Mood] = []
    private var islandOpen = false
    /// The island's open menu, so orbits run clear of it. A guess until the island first opens.
    private var menuSize = CGSize(width: 440, height: 330)
    /// Where the island is, as the island itself last reported it.
    private var island: IslandGeometry?

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
        swapFlow = WallpaperSwapFlow(pending: swap.restorePending)
        desktop.onVisibilityChange = { [weak self] in self?.updateMotion() }
    }

    func start() {
        // A swap left behind by a crash or a forced quit is put right first.
        perform(swapFlow.launched(locked: LockMonitor.screenIsLocked()))

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
                self?.swapFlow.displaysSlept()
                self?.updateMotion()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.displaysWoke()
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
        let moods = feed.lock?.inhabitants.map(\.mood) ?? []
        if swapFlow.phase == .swapping, moods != lastSwapMoods { perform(swapFlow.moodsChanged(now: now)) }
    }

    private func turnOff() {
        desktop.uninstall()
        lockLayer?.uninstall()
        calendar.stop()
        if feed.desk != nil { feed.desk = nil }
        if feed.lock != nil { feed.lock = nil }
        feed.effect.configure(mode: nil, geometry: nil, agents: [], reduceMotion: false)
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
        guard liveLockAvailable, let skyLight = SkyLight.shared else { return perform(swapFlow.lock(now: Date())) }
        if lockLayer == nil { lockLayer = LockLayer(feed: feed, skyLight: skyLight) }
        guard let lockLayer, lockLayer.isInstalled || lockLayer.install() else {
            return fallBack(because: "SkyLight refused a space")
        }
        lockLayer.show { [weak self] in self?.lockLayerChecked(visible: $0) }
    }

    /// The live layer's self-check: fall back only if it can't be seen while the displays are awake.
    private func lockLayerChecked(visible: Bool) {
        guard LockLayerCheck.shouldFallBack(windowVisible: visible, displaysAsleep: screensAsleep) else { return }
        fallBack(because: "the lock-screen window wasn't visible")
    }

    private func leaveLock() {
        lockLayer?.hide()
        // Ends a swap, or retries a restore that failed earlier.
        perform(swapFlow.unlock())
    }

    /// The live layer can't show here: remember that for this macOS build and swap the wallpaper instead.
    private func fallBack(because reason: String) {
        log.notice("Live lock screen unavailable (\(reason, privacy: .public)) on \(Self.osBuild, privacy: .public); using the wallpaper swap")
        UserDefaults.standard.set(Self.osBuild, forKey: Self.fallbackBuildKey)
        lockLayer?.uninstall()
        lockLayer = nil
        updateLockMode()
        if locked { perform(swapFlow.lock(now: Date())) }
    }

    // MARK: - Wallpaper swap (fallback)

    /// Carries out what the swap flow decided.
    private func perform(_ actions: [WallpaperSwapFlow.Action]) {
        for action in actions {
            switch action {
            case .begin:
                let ok = swap.begin()
                if !ok, lockMode != .unavailable { lockMode = .unavailable }
                perform(swapFlow.began(ok: ok, now: Date()))
            case .render:
                renderSwap()
            case let .restore(force):
                swap.restore(force: force) { [weak self] ok in
                    guard let self else { return }
                    if !ok { self.log.error("Couldn't restore the wallpaper; Settings offers to try again") }
                    self.perform(self.swapFlow.restoreFinished(ok: ok, now: Date()))
                }
            }
        }
        if restorePending != swapFlow.pending { restorePending = swapFlow.pending }
        updateSwapTimer()
    }

    private func renderSwap() {
        guard let state = feed.lock else { return }
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

    /// Redraws the swapped wallpaper every 30 seconds while it's swapped.
    private func updateSwapTimer() {
        guard swapFlow.phase == .swapping else {
            swapTimer?.invalidate()
            swapTimer = nil
            return
        }
        guard swapTimer == nil else { return }
        swapTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.perform(self.swapFlow.tick(now: Date()))
        }
    }

    /// The island opened or closed: the effect starts, or winds down and settles.
    func islandChanged(open: Bool, menu: CGSize, island: IslandGeometry) {
        islandOpen = open
        menuSize = menu
        self.island = island
        configureEffect()
        feed.effect.setOpen(open)
    }

    /// Sets the notch effect up for the scene now showing: Solar System always lights its sun; the other worlds
    /// form a black hole if the setting is on. None in Low Power Mode, or when the island isn't on the main display.
    private func configureEffect() {
        guard let desk = feed.desk, let screen = NSScreen.screens.first, let island,
              island.screenFrame == screen.frame, !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            return feed.effect.configure(mode: nil, geometry: nil, agents: [], reduceMotion: false)
        }
        let mode: NotchSimulation.Mode? = desk.kind == .solar ? .solar : prefs.wallpaperIslandEffect ? .blackHole : nil
        let size = screen.frame.size
        let geometry = NotchGeometry(screen: Vec2(size.width, size.height),
                                     notchCenterX: island.centerX - screen.frame.minX,
                                     notchBottom: island.notchHeight, notchWidth: island.notchWidth,
                                     menu: Vec2(menuSize.width, menuSize.height))
        let renderer = SceneRenderers.renderer(for: desk.kind)
        let agents = desk.inhabitants.map { inhabitant in
            let spot = renderer.spot(for: inhabitant, in: desk)
            return NotchAgent(id: inhabitant.id, home: Vec2(spot.x * size.width, spot.y * size.height),
                              urgency: NotchAgent.urgency(of: inhabitant.mood))
        }
        feed.effect.configure(mode: mode, geometry: geometry, agents: agents,
                              reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Puts the user's own wallpaper back. Settings' "Restore my wallpaper".
    func restoreWallpaper() {
        perform(swapFlow.retry())
    }

    // MARK: - Motion, displays and time

    private func updateMotion() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let desk = desktop.isVisible && !screensAsleep && !lowPower && !locked
        let mainDesk = desk && desktop.isMainVisible
        let lock = locked && !screensAsleep && !lowPower
        if feed.reduceMotion != reduce { feed.reduceMotion = reduce }
        if feed.deskAnimated != desk { feed.deskAnimated = desk }
        if feed.mainDeskAnimated != mainDesk { feed.mainDeskAnimated = mainDesk }
        if feed.lockAnimated != lock { feed.lockAnimated = lock }
        // Low Power Mode or Reduce Motion switched mid-effect: set it up again at once.
        configureEffect()
        if islandOpen { feed.effect.setOpen(true) }
    }

    private func screensChanged() {
        guard prefs.wallpaperEnabled else { return }
        desktop.install()
        if let lockLayer, lockLayer.isInstalled {
            lockLayer.install()   // starts hidden
            if locked, lockMode == .live { lockLayer.show { [weak self] in self?.lockLayerChecked(visible: $0) } }
        }
        perform(swapFlow.screensChanged(now: Date()))
        updateMotion()
    }

    /// Displays back on: redraw a swapped wallpaper, and look again at a live layer checked while they slept.
    private func displaysWoke() {
        perform(swapFlow.displaysWoke(now: Date()))
        if locked, lockMode == .live, let lockLayer, lockLayer.isInstalled {
            lockLayer.show { [weak self] in self?.lockLayerChecked(visible: $0) }
        }
        clockChanged()
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
