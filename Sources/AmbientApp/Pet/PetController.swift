import AmbientCore
import AppKit
import Combine
import SwiftUI

/// Runs the desktop pet: a floating panel you can drag anywhere, which shows the pet and its bubble and
/// intercepts the mouse only over them.
final class PetController {
    private let model: AppModel
    private let prefs: Preferences
    private let viewModel: PetViewModel
    private let panel: IslandPanel
    private var cancellables: Set<AnyCancellable> = []
    private var monitors: [Any] = []
    private var shown = false
    /// Where the pet stands, in global screen coordinates.
    private var origin: CGPoint
    private var drag: (mouse: CGPoint, origin: CGPoint)?
    private var dragging = false
    /// Keeps a run of sessions finishing at once to one cheer.
    private var gate = PetReactionGate()
    /// Opens or closes the list after the pointer has rested on, or left, the pet.
    private var hoverWork: DispatchWorkItem?
    /// After a click, the list stays shut until the pointer leaves, rather than springing open again.
    private var hoverSuppressed = false
    /// Opened without hovering (VoiceOver): stays open until a click elsewhere.
    private var listPinned = false
    private static let hoverDelay: TimeInterval = 0.25
    private static let unhoverDelay: TimeInterval = 0.3
    /// Moves under this many points are clicks.
    private static let dragThreshold: CGFloat = 3

    init(model: AppModel, prefs: Preferences, onSettings: @escaping () -> Void) {
        self.model = model
        self.prefs = prefs
        let visible = Self.visibleFrame(containing: prefs.petOrigin)
        origin = PetLayout.clamp(prefs.petOrigin ?? PetLayout.defaultOrigin(in: visible, pet: PetViewModel.petSize),
                                 pet: PetViewModel.petSize, in: visible)
        viewModel = PetViewModel(placement: PetLayout.place(pet: origin, petSize: PetViewModel.petSize,
                                                            panel: PetViewModel.panelSize, in: visible))

        panel = IslandPanel(contentRect: viewModel.placement.panel, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above your windows, below the menu bar and the island.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let host = FirstMouseHostingView(rootView: PetView(model: viewModel))
        host.frame = CGRect(origin: .zero, size: PetViewModel.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        viewModel.onOpen = { [weak self] session in
            self?.model.open(session)
            // Let the burst start under the pointer before the list folds away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.hoverSuppressed = true
                self?.viewModel.peekPinned = false
                self?.setExpanded(false)
            }
        }
        viewModel.onAcknowledgeAll = { [weak model] in model?.acknowledgeAll() }
        viewModel.onToggleQuiet = { [weak self] in
            guard let self else { return }
            self.model.setQuiet(for: self.prefs.isQuiet ? nil : 3_600)
            self.viewModel.quiet = self.prefs.isQuiet
        }
        viewModel.onSettings = { [weak self] in
            self?.setExpanded(false)
            onSettings()
        }
        viewModel.onHide = { [weak self] in self?.prefs.petEnabled = false }
        viewModel.onShowList = { [weak self] in
            self?.listPinned = true
            self?.viewModel.peekPinned = false
            self?.setExpanded(true)
        }
        viewModel.onDrag = { [weak self] phase in self?.handleDrag(phase) }
    }

    func start() {
        model.$sessions
            .sink { [weak self] sessions in
                self?.viewModel.sessions = sessions
                self?.trackPointer()
            }
            .store(in: &cancellables)
        model.transitions
            .sink { [weak self] t in
                guard let self, self.shown, let reaction = PetPolicy.announce(t, quiet: self.prefs.isQuiet),
                      self.gate.allow(reaction, at: Date()) else { return }
                self.viewModel.react(reaction)
            }
            .store(in: &cancellables)
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
        sync()
    }

    // MARK: - State

    /// Applies the settings: shown or hidden, which species, Quiet, and a reset position.
    private func sync() {
        viewModel.species = prefs.pet
        viewModel.quiet = prefs.isQuiet
        if !dragging {
            let wanted = prefs.petOrigin ?? PetLayout.defaultOrigin(in: Self.visibleFrame(containing: nil), pet: PetViewModel.petSize)
            if wanted != origin {
                origin = wanted
                layout()
            }
        }
        if prefs.petEnabled != shown { prefs.petEnabled ? show() : hide() }
    }

    private func show() {
        shown = true
        viewModel.visible = true
        layout()
        panel.orderFrontRegardless()
        viewModel.react(.wake)

        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in self?.trackPointer() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            self?.trackPointer()
            return event
        }) {
            monitors.append(m)
        }
        // A click anywhere else closes the peek and the list.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in self?.dismiss() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            if event.window !== self?.panel { self?.dismiss() }
            return event
        }) {
            monitors.append(m)
        }
    }

    private func hide() {
        shown = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hoverWork?.cancel()
        hoverWork = nil
        listPinned = false
        viewModel.peekPinned = false
        viewModel.expanded = false
        viewModel.visible = false
        panel.orderOut(nil)
    }

    private func setExpanded(_ expanded: Bool) {
        guard viewModel.expanded != expanded else { return }
        viewModel.expanded = expanded
        trackPointer()
    }

    private func dismiss() {
        listPinned = false
        if viewModel.peekPinned {
            viewModel.peekPinned = false
            trackPointer()
        }
        setExpanded(false)
    }

    /// Keeps the pet on its screen and fits the panel around it.
    private func layout() {
        let visible = Self.visibleFrame(containing: origin)
        origin = PetLayout.clamp(origin, pet: PetViewModel.petSize, in: visible)
        let placement = PetLayout.place(pet: origin, petSize: PetViewModel.petSize, panel: PetViewModel.panelSize, in: visible)
        if placement != viewModel.placement { viewModel.placement = placement }
        if panel.frame != placement.panel { panel.setFrame(placement.panel, display: true) }
        trackPointer()
    }

    // MARK: - Pointer

    private func handleDrag(_ phase: PetViewModel.DragPhase) {
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            guard let start = drag else {
                drag = (mouse, origin)
                return
            }
            let dx = mouse.x - start.mouse.x, dy = mouse.y - start.mouse.y
            if !dragging, hypot(dx, dy) >= Self.dragThreshold {
                dragging = true
                setExpanded(false)
            }
            guard dragging else { return }
            origin = CGPoint(x: start.origin.x + dx, y: start.origin.y + dy)
            layout()
        case .ended:
            if dragging {
                prefs.petOrigin = origin
                // Dropped under the pointer: don't spring the list open again until it leaves.
                hoverSuppressed = true
            } else {
                // A click pins the peek; the hovered list gives way to it until the pointer leaves.
                hoverWork?.cancel()
                hoverWork = nil
                hoverSuppressed = true
                listPinned = false
                viewModel.tapPet()
                trackPointer()
            }
            drag = nil
            dragging = false
        }
    }

    /// Lets clicks through everywhere but the pet and its bubble.
    private func trackPointer() {
        guard shown else { return }
        let point = NSEvent.mouseLocation
        let frame = panel.frame
        func onScreen(_ r: CGRect) -> CGRect {
            CGRect(x: frame.minX + r.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
        }
        let overPet = onScreen(viewModel.petRect).contains(point)
        let overContent = viewModel.contentRect.map(onScreen)?.contains(point) ?? false
        let inside = dragging || overPet || overContent
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        trackHover(overPet: overPet, inside: inside)
    }

    /// Like the island: resting on the pet opens the list, and leaving the pet and the list closes it. Never while
    /// the pet is being dragged, nor right after a click on it.
    private func trackHover(overPet: Bool, inside: Bool) {
        if !inside { hoverSuppressed = false }
        guard !dragging, drag == nil else {
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        let want = listPinned || (!hoverSuppressed && (viewModel.expanded ? inside : overPet))
        if want == viewModel.expanded {
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hoverWork = nil
            self?.setExpanded(want)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (want ? Self.hoverDelay : Self.unhoverDelay), execute: work)
    }

    /// The visible part (without menu bar and Dock) of the screen holding `point`, else of the screen with the menu bar.
    private static func visibleFrame(containing point: CGPoint?) -> CGRect {
        let screens = NSScreen.screens
        let center = point.map { CGPoint(x: $0.x + PetViewModel.petSize.width / 2, y: $0.y + PetViewModel.petSize.height / 2) }
        let screen = center.flatMap { c in screens.first { $0.frame.contains(c) } }
            ?? screens.first { $0.frame.contains(NSEvent.mouseLocation) && point != nil }
            ?? screens.first
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
