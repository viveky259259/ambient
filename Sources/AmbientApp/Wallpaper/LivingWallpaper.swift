import AmbientCore
import AppKit
import Combine
import os

/// Runs the living wallpaper: builds what the scene shows and decides where it's drawn.
final class LivingWallpaper: ObservableObject {
    let feed = SceneFeed()

    private let model: AppModel
    private let prefs: Preferences
    private let desktop: DesktopLayer
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var minuteTimer: Timer?
    private var slots: [String: Int] = [:]
    private var screensAsleep = false

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
        if !desktop.isInstalled { desktop.install() }
        updateMotion()
    }

    private func turnOff() {
        guard desktop.isInstalled || feed.desk != nil else { return }
        desktop.uninstall()
        feed.desk = nil
    }

    // MARK: - Motion, displays and time

    private func updateMotion() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let desk = desktop.isVisible && !screensAsleep && !lowPower
        if feed.reduceMotion != reduce { feed.reduceMotion = reduce }
        if feed.deskAnimated != desk { feed.deskAnimated = desk }
    }

    private func screensChanged() {
        guard prefs.wallpaperEnabled else { return }
        desktop.install()
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
