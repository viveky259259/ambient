import AmbientCore
import AppKit
import SwiftUI
import os

/// The lock-screen fallback. While the Mac is locked, the scene becomes the real wallpaper; on unlock, the user's
/// own wallpaper comes back exactly, from a backup of macOS's wallpaper store. The public API can't restore a
/// color or aerial wallpaper, which is why this backs up and restores the store itself.
final class WallpaperSwap {
    private let paths: AmbientPaths
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.wallpaper", qos: .userInitiated)

    init(paths: AmbientPaths) { self.paths = paths }

    var storeURL: URL { WallpaperStore.url(userHome: paths.userHome) }
    var backupURL: URL { paths.backups.appendingPathComponent("wallpaper-Index.plist") }
    var markerURL: URL { paths.home.appendingPathComponent("wallpaper-swapped") }
    var imagesDir: URL { paths.home.appendingPathComponent("wallpaper", isDirectory: true) }

    /// A swap started and hasn't been undone, e.g. Ambient quit while the Mac was locked.
    var restorePending: Bool { FileManager.default.fileExists(atPath: markerURL.path) }

    /// Whether the user's wallpaper store is one this knows how to put back.
    var isSupported: Bool { (try? Data(contentsOf: storeURL)).map(WallpaperStore.isKnownFormat) ?? false }

    /// Backs up the store and marks the swap. False when the store isn't in a format we know, or can't be backed up.
    func begin() -> Bool {
        // The backup from an unfinished swap is the user's real wallpaper; don't overwrite it with ours.
        if restorePending { return true }
        do {
            let data = try Data(contentsOf: storeURL)
            guard WallpaperStore.isKnownFormat(data) else {
                log.error("Wallpaper store format not recognized; not swapping")
                return false
            }
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: backupURL, options: .atomic)
            try Data().write(to: markerURL, options: .atomic)
            return true
        } catch {
            log.error("Couldn't back up the wallpaper store: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Sets one image per screen as the wallpaper. Each gets a new name, since macOS caches by URL.
    func show(_ images: [(screen: NSScreen, png: Data)]) {
        let previous = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        for (screen, png) in images {
            let url = imagesDir.appendingPathComponent("scene-\(UUID().uuidString).png")
            do {
                try png.write(to: url, options: .atomic)
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
                ])
            } catch {
                log.error("Couldn't set the lock-screen scene: \(error.localizedDescription, privacy: .public)")
            }
        }
        for url in previous { try? FileManager.default.removeItem(at: url) }
    }

    /// Puts the user's wallpaper back, off the main thread; `completion` runs on the main queue with whether the
    /// store now matches the backup.
    func restore(completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            let ok = restoreNow()
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private func restoreNow() -> Bool {
        guard restorePending else { return true }
        guard let backup = try? Data(contentsOf: backupURL) else {
            log.error("Wallpaper backup is missing; Settings will offer to restore")
            return false
        }
        // If none of Ambient's images is set any more (the user picked a new wallpaper after a crash), keep theirs.
        if let current = try? Data(contentsOf: storeURL), !WallpaperStore.references(directory: imagesDir, in: current) {
            cleanUp()
            return true
        }
        do {
            try backup.write(to: storeURL, options: .atomic)
        } catch {
            log.error("Couldn't restore the wallpaper store: \(error.localizedDescription, privacy: .public)")
            return false
        }
        restartWallpaperAgent()
        // The agent rewrites the store as it starts; give it a few seconds, then check it took.
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            if let now = try? Data(contentsOf: storeURL), WallpaperStore.matches(now, backup) {
                cleanUp()
                return true
            }
        }
        log.error("The wallpaper store doesn't match the backup after restoring")
        return false
    }

    private func restartWallpaperAgent() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["WallpaperAgent"]
        try? killall.run()
        killall.waitUntilExit()
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: markerURL)
        let images = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        for url in images { try? FileManager.default.removeItem(at: url) }
    }

    /// A PNG of a scene at a screen's native pixel size.
    @MainActor static func render(_ state: SceneState, for screen: NSScreen, showsText: Bool) -> Data? {
        let view = SceneView(state: state, showsText: showsText, animated: false)
            .frame(width: screen.frame.width, height: screen.frame.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = screen.backingScaleFactor
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
