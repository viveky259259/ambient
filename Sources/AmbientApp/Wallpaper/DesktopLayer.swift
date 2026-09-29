import AppKit
import SwiftUI

/// The living wallpaper at the desk: a click-through window per display, just above the real wallpaper and
/// below Finder's icons, on every Space. Nothing to restore: removing the windows is all it takes.
final class DesktopLayer {
    private let feed: SceneFeed
    private var windows: [WallpaperWindow] = []
    private var observers: [NSObjectProtocol] = []
    private var checkTimer: Timer?
    private var lastVisible: [Bool]?
    /// Called when the wallpaper becomes covered or uncovered.
    var onVisibilityChange: (() -> Void)?

    init(feed: SceneFeed) { self.feed = feed }

    var isInstalled: Bool { !windows.isEmpty }

    /// Whether any real part of the wallpaper can be seen right now. The menu bar and the Dock always show a strip
    /// of the desktop, so what counts is each display's visible frame, and whether app windows cover it.
    var isVisible: Bool {
        windows.contains { window in
            guard window.occlusionState.contains(.visible), let screen = window.screen else { return false }
            return !Self.appWindowsCover(screen.visibleFrame)
        }
    }

    /// Whether the main display's part of the wallpaper can be seen: where the island and its effect live.
    var isMainVisible: Bool {
        guard let window = windows.first, window.occlusionState.contains(.visible), let screen = window.screen else { return false }
        return !Self.appWindowsCover(screen.visibleFrame)
    }

    /// (Re)creates one window per display.
    func install() {
        uninstall()
        let main = NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.contentView = NSHostingView(rootView: SceneHost(feed: feed, surface: .desk, isMain: screen == main))
            window.orderFrontRegardless()
            windows.append(window)
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.recheck() })
        }
        // Moving or resizing app windows doesn't change our occlusion (the menu bar keeps us "visible"), so look again now and then.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.recheck() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        lastVisible = nil
        recheck()
    }

    func uninstall() {
        checkTimer?.invalidate()
        checkTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func recheck() {
        let visible = [isVisible, isMainVisible]
        guard visible != lastVisible else { return }
        lastVisible = visible
        onVisibilityChange?()
    }

    /// Whether ordinary app windows cover `frame` (AppKit coordinates), sampled on a 12 × 8 grid.
    static func appWindowsCover(_ frame: CGRect) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let rects: [CGRect] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            // Window-server coordinates start at the top-left of the main display; AppKit's at the bottom-left.
            return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        guard !rects.isEmpty else { return false }
        for column in 0..<12 {
            for row in 0..<8 {
                let point = CGPoint(x: frame.minX + frame.width * (CGFloat(column) + 0.5) / 12,
                                    y: frame.minY + frame.height * (CGFloat(row) + 0.5) / 8)
                if !rects.contains(where: { $0.contains(point) }) { return false }
            }
        }
        return true
    }
}
