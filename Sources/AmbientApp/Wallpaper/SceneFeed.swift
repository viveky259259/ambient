import AmbientCore
import AppKit
import Combine
import SwiftUI

/// What the wallpaper windows draw. Every window observes the same feed.
final class SceneFeed: ObservableObject {
    @Published var desk: SceneState?
    @Published var lock: SceneState?
    @Published var deskAnimated = false
    /// The displays whose desk can be seen right now, by frame: only those move.
    @Published var visibleDesks: [CGRect] = []
    /// The display the notch effect plays on: the one with the island.
    @Published var effectScreen: CGRect?
    @Published var lockAnimated = false
    @Published var reduceMotion = false
    /// The notch effect, drawn only by the desk scene on the main display.
    let effect = NotchEffectEngine()
}

/// One display's wallpaper. At the desk every display shows the full scene, and moves only while its own part of the
/// desktop can be seen; the display with the island also plays the notch effect. On the lock screen the main display
/// shows the full scene and the others the world alone.
struct SceneHost: View {
    @ObservedObject var feed: SceneFeed
    let surface: SceneSurface
    let isMain: Bool
    /// This display's frame, to match against the visible desks and the effect's display.
    var screen: CGRect = .zero

    var body: some View {
        if surface == .desk, let state = feed.desk {
            let animated = feed.deskAnimated && feed.visibleDesks.contains(screen)
            if feed.effectScreen == screen {
                EffectSceneView(state: state, effect: feed.effect, animated: animated, reduceMotion: feed.reduceMotion)
            } else {
                SceneView(state: state, animated: animated, reduceMotion: feed.reduceMotion)
            }
        } else if surface == .lock, let state = feed.lock {
            SceneView(state: isMain ? state : state.scenery(), showsText: isMain, animated: feed.lockAnimated,
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
