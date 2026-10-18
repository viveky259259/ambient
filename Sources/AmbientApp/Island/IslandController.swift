import AmbientCore
import AppKit
import Combine
import SwiftUI

/// A panel that never takes focus from the app you're working in.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clicks land on the first try even though the panel is never key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Runs the notch island: decides what it shows, and tracks the pointer so it only intercepts
/// clicks over its own shape.
final class IslandController {
    private let model: AppModel
    private let prefs: Preferences
    private let speech: SpeechController
    private let viewModel: IslandViewModel
    private let panel: IslandPanel
    private var cancellables: Set<AnyCancellable> = []
    private var monitors: [Any] = []
    private var bloomID: String?
    private var bloomTimer: Timer?
    private var hovering = false
    private var hoverWork: DispatchWorkItem?
    /// After a click, stay collapsed until the pointer leaves, rather than springing open again.
    private var hoverSuppressed = false
    /// Called when the menu opens, closes or changes size, with the open menu's size and where the island is.
    var onMenuChange: ((Bool, CGSize, IslandGeometry) -> Void)?
    /// The open menu's size and place as last reported; nil while it's closed.
    private var reportedMenu: (size: CGSize, geometry: IslandGeometry)?

    init?(model: AppModel, prefs: Preferences, speech: SpeechController, onSettings: @escaping () -> Void) {
        guard let geometry = IslandGeometry.current() else { return nil }
        self.model = model
        self.prefs = prefs
        self.speech = speech
        viewModel = IslandViewModel(geometry: geometry)

        panel = IslandPanel(contentRect: geometry.panelFrame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let host = FirstMouseHostingView(rootView: IslandView(model: viewModel))
        host.frame = CGRect(origin: .zero, size: geometry.panelFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        viewModel.onOpen = { [weak self] session in
            self?.endHover()
            self?.model.open(session)
        }
        viewModel.onAcknowledgeAll = { [weak model] in model?.acknowledgeAll() }
        viewModel.onToggleQuiet = { [weak self] in
            guard let self else { return }
            self.model.setQuiet(for: self.prefs.isQuiet ? nil : 3_600)
            self.viewModel.quiet = self.prefs.isQuiet
        }
        viewModel.onSettings = { [weak self] in
            self?.endHover()
            onSettings()
        }
        viewModel.onToggleShowAll = { [weak self] in
            guard let self else { return }
            self.viewModel.showingAll.toggle()
            self.reportMenu()
            self.trackPointer()
        }
        viewModel.onStopSpeech = { [weak speech] in speech?.stop() }
        viewModel.onUseMacVoice = { [weak speech] in speech?.useMacVoice() }
    }

    func start() {
        panel.orderFrontRegardless()

        model.$sessions
            .sink { [weak self] sessions in
                self?.viewModel.sessions = sessions
                self?.refresh()
            }
            .store(in: &cancellables)
        model.transitions
            .sink { [weak self] t in self?.handle(t) }
            .store(in: &cancellables)
        speech.$state
            .sink { [weak self] state in
                self?.viewModel.speech = state
                self?.refresh()
            }
            .store(in: &cancellables)
        speech.$level
            .sink { [weak self] in self?.viewModel.speechLevel = $0 }
            .store(in: &cancellables)
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.viewModel.quiet = self?.prefs.isQuiet ?? false
                self?.refresh()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.relocate() }
            .store(in: &cancellables)

        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in self?.trackPointer() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            self?.trackPointer()
            return event
        }) {
            monitors.append(local)
        }
    }

    // MARK: - State

    private func handle(_ t: SessionChange) {
        if let duration = IslandPolicy.bloomDuration(for: t, quiet: prefs.isQuiet), prefs.islandEnabled {
            bloomID = t.session.id
            bloomTimer?.invalidate()
            bloomTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.bloomID = nil
                self?.refresh()
            }
        } else if t.session.id == bloomID, !AlertPolicy.attentionMoods.contains(t.session.mood) || t.removed {
            // What we were announcing is resolved (permission granted, result seen).
            bloomID = nil
            bloomTimer?.invalidate()
        }
        refresh()
    }

    private func refresh() {
        let sessions = viewModel.sessions
        let next: IslandViewModel.Presentation
        if !prefs.islandEnabled {
            next = .hidden
        } else if viewModel.speech != .idle {
            // Ahead of hovering, so reaching for the stop button doesn't swap it for the session list.
            next = .speech
        } else if hovering || UserDefaults.standard.bool(forKey: "debugForceExpanded") {
            next = .expanded
        } else if let id = bloomID, sessions.contains(where: { $0.id == id }) {
            next = .bloom(id)
        } else if IslandPolicy.isVisible(sessions, showWhileWorking: prefs.islandShowsWorking) {
            next = .collapsed
        } else {
            next = .hidden
        }
        if next != viewModel.presentation {
            // Each time it opens, the island starts with the short list.
            if next != .expanded { viewModel.showingAll = false }
            viewModel.presentation = next
        }
        reportMenu()
        trackPointer()
    }

    /// Tells `onMenuChange` when the menu opens or closes, and when sessions or the display resize it while open.
    private func reportMenu() {
        let size = viewModel.size(for: .expanded), geometry = viewModel.geometry
        if viewModel.presentation == .expanded {
            if let last = reportedMenu, last.size == size, last.geometry == geometry { return }
            reportedMenu = (size, geometry)
            onMenuChange?(true, size, geometry)
        } else if reportedMenu != nil {
            reportedMenu = nil
            onMenuChange?(false, size, geometry)
        }
    }

    private func relocate() {
        guard let geometry = IslandGeometry.current(), geometry != viewModel.geometry else { return }
        viewModel.geometry = geometry
        panel.setFrame(geometry.panelFrame, display: true)
        refresh()
    }

    // MARK: - Pointer

    private func trackPointer() {
        let point = NSEvent.mouseLocation
        // Hidden, a notch still opens the island when there are sessions. Without a notch there's nothing to see, so
        // the top center of the menu bar opens it whenever you hover there, even with no sessions.
        let active = viewModel.presentation != .hidden
            || (prefs.islandEnabled && (viewModel.geometry.hasNotch ? !viewModel.sessions.isEmpty : true))
        var hot = viewModel.geometry.screenRect(for: viewModel.currentSize)
        hot.size.height += 2 // include the very top pixel row
        let inside = active && hot.contains(point)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if !inside { hoverSuppressed = false }

        if inside, !hovering, !hoverSuppressed {
            scheduleHover(true, after: viewModel.presentation == .hidden ? 0.3 : 0.12)
        } else if !inside, hovering {
            scheduleHover(false, after: 0.3)
        } else {
            hoverWork?.cancel()
            hoverWork = nil
        }
    }

    private func scheduleHover(_ on: Bool, after delay: TimeInterval) {
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            self.hovering = on
            self.refresh()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func endHover() {
        hoverWork?.cancel()
        hoverWork = nil
        hovering = false
        hoverSuppressed = true
        bloomID = nil
        refresh()
    }
}
