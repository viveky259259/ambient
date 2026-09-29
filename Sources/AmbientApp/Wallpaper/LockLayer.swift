import AmbientCore
import AppKit
import SwiftUI

/// The living wallpaper on the lock screen, live: a window per display in a SkyLight space above the lock
/// screen. That space floats above everything, so the windows stay invisible and click-through until the Mac locks.
final class LockLayer {
    private let feed: SceneFeed
    private let skyLight: SkyLight
    private var space: Int32?
    private var windows: [WallpaperWindow] = []
    private var check: DispatchWorkItem?

    init(feed: SceneFeed, skyLight: SkyLight) {
        self.feed = feed
        self.skyLight = skyLight
    }

    var isInstalled: Bool { !windows.isEmpty }

    /// (Re)creates the windows, hidden. False if SkyLight refused a space.
    @discardableResult
    func install() -> Bool {
        uninstall()
        if space == nil { space = skyLight.makeLockScreenSpace() }
        guard let space else { return false }
        let main = NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.isOpaque = false
            window.alphaValue = 0
            window.contentView = NSHostingView(rootView: SceneHost(feed: feed, surface: .lock, isMain: screen == main))
            window.orderFrontRegardless()
            skyLight.move(window, to: space)
            windows.append(window)
        }
        return true
    }

    func uninstall() {
        check?.cancel()
        windows.forEach {
            $0.alphaValue = 0
            $0.orderOut(nil)
        }
        windows = []
    }

    /// Fades in over the lock screen, then reports whether it can actually be seen.
    func show(report: @escaping (_ visible: Bool) -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        check?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.windows.isEmpty else { return }
            report(self.windows.contains { $0.occlusionState.contains(.visible) })
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Gone at once.
    func hide() {
        check?.cancel()
        windows.forEach { $0.alphaValue = 0 }
    }
}
