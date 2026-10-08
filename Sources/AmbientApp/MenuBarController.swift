import AmbientCore
import AppKit
import Combine

/// A status item tinted by the aggregate mood, with the session list one click away.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let prefs: Preferences
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private let onSettings: () -> Void
    private let onDemo: () -> Void

    init(model: AppModel, prefs: Preferences, onSettings: @escaping () -> Void, onDemo: @escaping () -> Void) {
        self.model = model
        self.prefs = prefs
        self.onSettings = onSettings
        self.onDemo = onDemo
        super.init()
    }

    func start() {
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "Ambient"
        model.$sessions
            .combineLatest(prefs.$quietUntil)
            .sink { [weak self] _, _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()
    }

    private func updateIcon() {
        guard let button = item.button else { return }
        let mood = model.mood
        let primary = IslandPolicy.primary(model.sessions)
        button.image = Self.icon(mood: mood, color: primary?.moodTint.nsColor, quiet: prefs.isQuiet)
        let waiting = model.sessions.filter { $0.mood == .waiting }.count
        button.title = waiting > 1 ? " \(waiting)" : ""
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("Ambient: \(Describe.mood(mood))")
    }

    /// A ring when idle (template, so it follows the menu bar), a colored orb otherwise.
    private static func icon(mood: Mood, color: NSColor?, quiet: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let orb = rect.insetBy(dx: 4, dy: 4)
            if mood == .idle || color == nil {
                let ring = NSBezierPath(ovalIn: orb.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                NSColor.black.setStroke()
                ring.stroke()
            } else if let color {
                color.withAlphaComponent(0.35).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
                color.setFill()
                NSBezierPath(ovalIn: orb).fill()
            }
            if quiet {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3, y: 3))
                slash.line(to: NSPoint(x: 15, y: 15))
                slash.lineWidth = 1.6
                (mood == .idle ? NSColor.black : NSColor.labelColor).setStroke()
                slash.stroke()
            }
            return true
        }
        image.isTemplate = mood == .idle || color == nil
        return image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let sessions = model.sessions
        let header = sessions.isEmpty ? "No agent sessions" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s") · \(Describe.mood(model.mood))"
        menu.addItem(NSMenuItem(title: header, action: nil, keyEquivalent: ""))

        if !sessions.isEmpty { menu.addItem(.separator()) }
        let now = Date()
        for s in sessions.prefix(12) {
            let row = NSMenuItem(title: "", action: #selector(openSession(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = s.id
            let meta = [s.agent.displayName, Describe.place(s), Describe.clock(s, now: now), Describe.took(s)].compactMap { $0 }.joined(separator: " · ")
            let text = NSMutableAttributedString(string: Trim.truncate(Describe.title(s), max: 48), attributes: [.font: NSFont.menuFont(ofSize: 13)])
            text.append(NSAttributedString(string: "  \(meta)\n",
                                           attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            text.append(NSAttributedString(string: Trim.truncate(Describe.activity(s.activity), max: 60),
                                           attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            row.attributedTitle = text
            row.image = Self.dot(s.tint.nsColor, dim: s.mood == .idle)
            if let app = HostActivator.appName(for: s.host) { row.toolTip = "Open \(app)" }
            menu.addItem(row)
        }

        menu.addItem(.separator())
        if sessions.contains(where: { $0.mood == .done || $0.mood == .error }) {
            menu.addItem(item("Mark All as Seen", #selector(acknowledgeAll)))
        }
        if prefs.isQuiet, let until = prefs.quietUntil {
            let f = DateFormatter()
            f.timeStyle = .short
            menu.addItem(item("Resume Alerts (quiet until \(f.string(from: until)))", #selector(resume)))
        } else {
            let quiet = NSMenuItem(title: "Quiet Alerts", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, seconds) in [("For 1 Hour", 3_600.0), ("For 3 Hours", 10_800.0), ("Until Tomorrow", Self.secondsUntilTomorrow())] {
                let i = item(title, #selector(quietFor(_:)))
                i.representedObject = seconds
                sub.addItem(i)
            }
            quiet.submenu = sub
            menu.addItem(quiet)
        }
        let pet = item("Show Desktop Pet", #selector(togglePet))
        pet.state = prefs.petEnabled ? .on : .off
        menu.addItem(pet)
        menu.addItem(item("Play Demo", #selector(demo)))
        menu.addItem(.separator())
        menu.addItem(item("Suggest a Feature…", #selector(suggestFeature)))
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(item("Quit Ambient", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private static func dot(_ color: NSColor, dim: Bool) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.withAlphaComponent(dim ? 0.35 : 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private static func secondsUntilTomorrow() -> TimeInterval {
        let cal = Calendar.current
        let tomorrow = cal.date(bySettingHour: 8, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date())!)!
        return tomorrow.timeIntervalSinceNow
    }

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let s = model.sessions.first(where: { $0.id == id }) else { return }
        model.open(s)
    }

    @objc private func acknowledgeAll() { model.acknowledgeAll() }
    @objc private func resume() { model.setQuiet(for: nil) }
    @objc private func quietFor(_ sender: NSMenuItem) { model.setQuiet(for: sender.representedObject as? TimeInterval) }
    @objc private func togglePet() { prefs.petEnabled.toggle() }
    @objc private func demo() { onDemo() }
    @objc private func suggestFeature() { NSWorkspace.shared.open(FeatureRequests.url()) }
    @objc private func settings() { onSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
