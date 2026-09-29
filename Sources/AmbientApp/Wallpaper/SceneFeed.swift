import AmbientCore
import AppKit
import Combine
import SwiftUI

/// What the wallpaper windows draw. Every window observes the same feed.
final class SceneFeed: ObservableObject {
    @Published var desk: SceneState?
    @Published var lock: SceneState?
    @Published var deskAnimated = false
    @Published var lockAnimated = false
    @Published var reduceMotion = false
}

/// One display's wallpaper: the full scene on the main display, the world alone elsewhere.
struct SceneHost: View {
    @ObservedObject var feed: SceneFeed
    let surface: SceneSurface
    let isMain: Bool

    var body: some View {
        if let state = surface == .desk ? feed.desk : feed.lock {
            SceneView(state: isMain ? state : state.scenery(), showsText: isMain,
                      animated: surface == .desk ? feed.deskAnimated : feed.lockAnimated,
                      reduceMotion: feed.reduceMotion)
        } else {
            Color.black
        }
    }
}

/// A borderless, click-through window that never becomes key or main: the wallpaper can't take focus.
final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        backgroundColor = .black
        setFrame(screen.frame, display: false)
    }
}
