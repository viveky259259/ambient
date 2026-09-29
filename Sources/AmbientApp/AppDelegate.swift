import AmbientCore
import AppKit
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "app")
    private let paths = AmbientPaths.current()
    private let prefs = Preferences.shared
    private lazy var model = AppModel(prefs: prefs, stateURL: paths.stateFile, dayURL: paths.dayFile,
                                      titles: SessionTitles(userHome: paths.userHome))
    private var server: EventServer?
    private var island: IslandController?
    private var notifier: Notifier?
    private var menuBar: MenuBarController?
    private var dockGlow: DockGlow?
    private var wallpaper: LivingWallpaper?
    private var setupWindow: NSWindow?
    private var setupModel: SetupModel?
    private var demoTimers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UnixSocketServer.isListening(paths.socket.path) {
            log.notice("Another Ambient is already running; quitting.")
            NSApp.terminate(nil)
            return
        }

        do {
            try paths.ensureHome()
            linkCommandLineTool()
        } catch {
            log.error("Couldn't prepare \(self.paths.home.path): \(error.localizedDescription)")
        }
        healHooks()

        model.start()
        let server = EventServer(paths: paths, model: model)
        do { try server.start() } catch { log.error("Socket server failed: \(String(describing: error))") }
        self.server = server

        let notifier = Notifier(model: model, prefs: prefs)
        notifier.start()
        self.notifier = notifier

        island = IslandController(model: model, prefs: prefs) { [weak self] in self?.showSetup() }
        island?.start()

        menuBar = MenuBarController(model: model, prefs: prefs,
                                    onSettings: { [weak self] in self?.showSetup() },
                                    onDemo: { [weak self] in self?.playDemo() })
        menuBar?.start()

        dockGlow = DockGlow(model: model, prefs: prefs)
        dockGlow?.start()

        let wallpaper = LivingWallpaper(model: model, prefs: prefs, paths: paths)
        wallpaper.start()
        self.wallpaper = wallpaper
        island?.onMenuChange = { [weak wallpaper] open, menu, geometry in
            wallpaper?.islandChanged(open: open, menu: menu, island: geometry)
        }

        if !prefs.setupCompleted { showSetup() } else { askForNotificationsOnce() }
    }

    /// The system prompt appears only while permission is undecided.
    private func askForNotificationsOnce() {
        guard prefs.notificationsEnabled, let notifier else { return }
        notifier.authorizationStatus { status in
            if status == .notDetermined { notifier.requestAuthorization() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
        server?.stop()
    }

    /// Opening the app again (Finder, Spotlight, `open -a Ambient`) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return false
    }

    // MARK: - Setup window

    func showSetup() {
        if setupWindow == nil, let notifier, let wallpaper {
            let setup = SetupModel(paths: paths, notifier: notifier)
            let view = SettingsView(setup: setup, prefs: prefs, wallpaper: wallpaper,
                                    onDemo: { [weak self] in self?.playDemo() },
                                    onPreviewSound: { [weak notifier] in notifier?.preview($0) },
                                    onDone: { [weak self] in
                                        self?.prefs.setupCompleted = true
                                        self?.setupWindow?.close()
                                        self?.askForNotificationsOnce()
                                    })
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = [.minSize, .maxSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ambient"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // An empty unified toolbar gives the title bar the height that seats the traffic lights
            // inside the floating sidebar.
            window.toolbar = NSToolbar(identifier: "settings")
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(Theme.Layout.windowSize)
            window.center()
            setupModel = setup
            setupWindow = window
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.prefs.setupCompleted = true
                NSApp.setActivationPolicy(.accessory)
            }
        }
        // Show in the Dock and app switcher while the window is open, like a regular settings window.
        NSApp.setActivationPolicy(.regular)
        setupModel?.refresh()
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Demo

    func playDemo() {
        demoTimers.forEach { $0.invalidate() }
        demoTimers = []
        // Hosted by Ambient itself, so the demo never counts as "you're already looking".
        let host = HostInfo(bundleId: "com.viveky259259.Ambient.demo")
        for (i, step) in Demo.tour.enumerated() {
            let timer = Timer.scheduledTimer(withTimeInterval: Double(i) * 3 + 0.3, repeats: false) { [weak self] _ in
                for e in Demo.events(for: step.mood, agent: step.agent, project: step.project, message: step.message, host: host) {
                    self?.model.apply(e)
                }
            }
            demoTimers.append(timer)
        }
        let end = Double(Demo.tour.count) * 3 + 15
        demoTimers.append(Timer.scheduledTimer(withTimeInterval: end, repeats: false) { [weak self] _ in
            Demo.tourCleanup(host: host).forEach { self?.model.apply($0) }
        })
    }

    // MARK: - Hooks

    /// Keeps ~/.ambient/bin/ambient pointing at the CLI inside this bundle, wherever the app lives.
    private func linkCommandLineTool() {
        let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ambient")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { return }
        let link = paths.cliLink
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == cli.path { return }
        try? fm.removeItem(at: link)
        do { try fm.createSymbolicLink(at: link, withDestinationURL: cli) } catch {
            log.error("Couldn't link the command-line tool: \(error.localizedDescription)")
        }
    }

    /// Repairs hooks the user installed before, e.g. after an update changed the events.
    private func healHooks() {
        let installer = HookInstaller(paths: paths)
        for agent in AgentKind.allCases where installer.status(agent) == .partial {
            do {
                try installer.install(agent)
                log.notice("Updated \(agent.rawValue) hooks")
            } catch {
                log.error("Couldn't update \(agent.rawValue) hooks: \(String(describing: error))")
            }
        }
    }
}
