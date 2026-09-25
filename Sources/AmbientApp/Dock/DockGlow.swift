import AmbientCore
import AppKit
import Combine
import QuartzCore

/// Light along the Dock's edge of the screen, in the color of what the agents are doing.
///
/// macOS doesn't let apps draw inside the Dock, but the Dock's glass blurs whatever sits behind it.
/// A click-through window one level below the Dock paints a soft floor of light along the edge,
/// and — with Accessibility access — a brighter, feathered layer exactly behind the Dock's glass.
final class DockGlow {
    private let model: AppModel
    private let prefs: Preferences
    private let window: NSWindow
    private let root = CALayer()
    private let floor = CAGradientLayer()
    private let pill = CALayer()
    private let pillMask = CALayer()
    private let locator = DockLocator()
    private var cancellables: Set<AnyCancellable> = []
    private var locateTimer: Timer?
    private var style: GlowStyle?
    private var edge: DockLocator.Edge = .bottom
    private var lastLayout: (CGRect, CGRect?)?
    private var shown = false

    /// Thickness of the edge light when the Dock reserves no space (auto-hide).
    private let edgeLight: CGFloat = 14

    init(model: AppModel, prefs: Preferences) {
        self.model = model
        self.prefs = prefs
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let view = NSView()
        view.wantsLayer = true
        view.layer = root
        root.addSublayer(floor)
        root.addSublayer(pill)
        pill.mask = pillMask
        floor.locations = [0, 0.45, 1]
        window.contentView = view
    }

    func start() {
        model.$sessions
            .combineLatest(prefs.$dockGlowEnabled, prefs.$dockGlowIntensity)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.update() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.relocate(force: true) }
            .store(in: &cancellables)
    }

    private func update() {
        let primary = IslandPolicy.primary(model.sessions)
        let next = prefs.dockGlowEnabled ? primary.flatMap { GlowStyle.for(mood: $0.mood, agent: $0.agent) } : nil
        if next == style {
            // Same state; the intensity may have changed.
            applyColors()
            return
        }
        let previous = style
        style = next
        guard let next else { return fade(in: false) }

        relocate(force: true)
        applyColors()
        animate(next, from: previous)
        fade(in: true)
    }

    private func applyColors() {
        guard let style else { return }
        let k = CGFloat(prefs.dockGlowIntensity)
        let c = style.color.nsColor
        let floorSize = lastLayout?.0.size ?? .zero
        let thin = (edge == .bottom ? floorSize.height : floorSize.width) <= edgeLight + 1
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.8)
        floor.colors = [c.withAlphaComponent((thin ? 0.95 : 0.7) * k).cgColor,
                        c.withAlphaComponent((thin ? 0.35 : 0.28) * k).cgColor,
                        c.withAlphaComponent(0).cgColor]
        pill.backgroundColor = c.withAlphaComponent(0.85 * k).cgColor
        CATransaction.commit()
    }

    private func animate(_ style: GlowStyle, from previous: GlowStyle?) {
        root.removeAllAnimations()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let steady = Float((style.low + style.high) / 2)

        if reduceMotion {
            root.opacity = steady
            return
        }
        if let period = style.period {
            root.opacity = Float(style.low)
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = style.low
            breathe.toValue = style.high
            breathe.duration = period / 2
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            root.add(breathe, forKey: "breathe")
        } else {
            // Arrive with a flourish, then settle: a bloom for done, two pulses for an error.
            root.opacity = steady
            let arrive = CAKeyframeAnimation(keyPath: "opacity")
            arrive.values = style.color == Palette.error ? [0.15, 1, 0.25, 1, steady] : [0.2, 1, steady]
            arrive.duration = style.color == Palette.error ? 1.3 : 1.1
            arrive.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            root.add(arrive, forKey: "arrive")
        }
    }

    private func fade(in visible: Bool) {
        guard visible != shown else { return }
        shown = visible
        if visible {
            window.orderFrontRegardless()
            startTracking()
        } else {
            stopTracking()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = visible ? 0.6 : 1.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.shown else { return }
            self.window.orderOut(nil)
            self.root.removeAllAnimations()
        })
    }

    // MARK: - Layout

    private func startTracking() {
        guard locateTimer == nil else { return }
        // Follow an auto-hiding Dock closely while it slides; a fixed Dock rarely moves.
        let interval = DockLocator.autohides && DockLocator.isTrusted ? 1.0 / 20 : 1.0
        locateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.relocate(force: false) }
        locateTimer?.tolerance = interval / 4
    }

    private func stopTracking() {
        locateTimer?.invalidate()
        locateTimer = nil
    }

    private func relocate(force: Bool) {
        let dock = locator.platterFrame()
        let screen = dock.flatMap { d in NSScreen.screens.first { $0.frame.intersects(d) } } ?? NSScreen.screens.first
        guard let screen else { return }
        let f = screen.frame, v = screen.visibleFrame

        if let dock, f.intersects(dock) {
            let gaps: [(DockLocator.Edge, CGFloat)] = [(.bottom, dock.minY - f.minY), (.left, dock.minX - f.minX), (.right, f.maxX - dock.maxX)]
            edge = gaps.min { $0.1 < $1.1 }!.0
        } else {
            edge = DockLocator.preferredEdge
        }

        let visibleDock = dock.flatMap { f.intersects($0) ? $0 : nil }
        let floorRect: CGRect
        switch edge {
        case .bottom:
            let top = max(v.minY, visibleDock?.maxY ?? f.minY, f.minY + edgeLight)
            floorRect = CGRect(x: f.minX, y: f.minY, width: f.width, height: top - f.minY)
        case .left:
            let right = max(v.minX, visibleDock?.maxX ?? f.minX, f.minX + edgeLight)
            floorRect = CGRect(x: f.minX, y: f.minY, width: right - f.minX, height: f.height)
        case .right:
            let left = min(v.maxX, visibleDock?.minX ?? f.maxX, f.maxX - edgeLight)
            floorRect = CGRect(x: left, y: f.minY, width: f.maxX - left, height: f.height)
        }

        if !force, let last = lastLayout, last.0 == floorRect, last.1 == visibleDock { return }
        let thicknessChanged = lastLayout.map { $0.0.size != floorRect.size } ?? true
        lastLayout = (floorRect, visibleDock)
        window.setFrame(floorRect, display: false)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: floorRect.size)
        floor.frame = bounds
        switch edge {
        case .bottom: floor.startPoint = CGPoint(x: 0.5, y: 0); floor.endPoint = CGPoint(x: 0.5, y: 1)
        case .left: floor.startPoint = CGPoint(x: 0, y: 0.5); floor.endPoint = CGPoint(x: 1, y: 0.5)
        case .right: floor.startPoint = CGPoint(x: 1, y: 0.5); floor.endPoint = CGPoint(x: 0, y: 0.5)
        }
        if let visibleDock {
            let p = visibleDock.offsetBy(dx: -floorRect.minX, dy: -floorRect.minY)
            pill.isHidden = false
            pill.frame = p
            pillMask.frame = CGRect(origin: .zero, size: p.size)
            pillMask.contents = Self.featheredMask(size: p.size, scale: window.backingScaleFactor)
        } else {
            pill.isHidden = true
        }
        CATransaction.commit()
        if thicknessChanged { applyColors() }
    }

    /// A rounded rect with softly faded edges, so the color never shows past the Dock's glass.
    private static func featheredMask(size: CGSize, scale: CGFloat) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceGray(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let inset: CGFloat = 2, feather: CGFloat = 8, radius = min(size.height / 2, 24)
        let steps = 16
        for s in 0..<steps {
            let t = CGFloat(s) / CGFloat(steps - 1)
            let r = CGRect(origin: .zero, size: size).insetBy(dx: inset + feather * t, dy: inset + feather * t)
            guard r.width > 0, r.height > 0 else { break }
            let cr = max(0, min(radius - feather * t, r.height / 2))
            ctx.setFillColor(gray: 1, alpha: t * t * (3 - 2 * t))
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil))
            ctx.fillPath()
        }
        return ctx.makeImage()
    }
}
