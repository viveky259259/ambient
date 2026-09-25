import AmbientCore
import AppKit

/// Finds and focuses the app an agent session runs in.
enum HostActivator {
    /// `TERM_PROGRAM` values for terminals that don't pass their bundle id down.
    private static let termPrograms: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "WezTerm": "com.github.wez.wezterm",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "Hyper": "co.zeit.hyper",
        "Tabby": "org.tabby",
        "kitty": "net.kovidgoyal.kitty",
        "zed": "dev.zed.Zed",
    ]

    static func app(for host: HostInfo?) -> NSRunningApplication? {
        guard let host else { return nil }
        if let id = host.bundleId, let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            return app
        }
        for pid in host.pids {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
        }
        if let program = host.termProgram, let id = termPrograms[program] {
            return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        }
        return nil
    }

    /// Brings the host app forward. Goes through LaunchServices, which works even though Ambient
    /// itself is never the active app.
    @discardableResult
    static func activate(_ host: HostInfo?) -> Bool {
        guard let app = app(for: host) else { return false }
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        } else {
            app.activate()
        }
        return true
    }

    static func isFrontmost(_ host: HostInfo?) -> Bool {
        guard let host, let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let id = host.bundleId, front.bundleIdentifier == id { return true }
        return host.pids.contains(front.processIdentifier)
    }

    static func appName(for host: HostInfo?) -> String? {
        app(for: host)?.localizedName
    }
}
