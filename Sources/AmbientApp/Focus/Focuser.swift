import AmbientCore
import AppKit
import ApplicationServices
import os

/// Brings the user back to a session: the exact chat, tab, pane or window when the host allows it,
/// otherwise the host app. Routes come from `FocusPlanner`; this runs them.
final class Focuser {
    private enum Outcome {
        /// The session is in front and its app is active.
        case done
        /// The session's tab or window is selected; its app still needs activating.
        case focused
        /// A preparatory step worked (e.g. the tmux pane); keep going.
        case prepared
        case failed
    }

    private let queue = DispatchQueue(label: "ambient.focus", qos: .userInitiated)
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "focus")

    func focus(_ session: Session) {
        var session = session
        // Some agents (Codex's app) don't pass __CFBundleIdentifier down; find the app from the process chain.
        if session.host != nil, session.host?.bundleId == nil,
           let id = HostActivator.app(for: session.host)?.bundleIdentifier {
            session.host?.bundleId = id
        }
        let routes = FocusPlanner.routes(for: session)
        let host = session.host
        queue.async { [self] in
            for route in routes {
                let outcome = run(route, host: host)
                log.debug("focus \(session.id, privacy: .public): \(String(describing: route), privacy: .public) → \(String(describing: outcome), privacy: .public)")
                switch outcome {
                case .done: return
                case .focused:
                    DispatchQueue.main.async { HostActivator.activate(host) }
                    return
                case .prepared, .failed: continue
                }
            }
        }
    }

    private func run(_ route: FocusRoute, host: HostInfo?) -> Outcome {
        switch route {
        case let .openURL(string):
            return openURL(string, host: host) ? .done : .failed
        case let .tmuxPane(socket, pane):
            let base = socket.map { ["-S", $0] } ?? []
            let window = Tools.run(Tools.tmux, base + ["select-window", "-t", pane])
            let paneOK = Tools.run(Tools.tmux, base + ["select-pane", "-t", pane])
            return window != nil && paneOK != nil ? .prepared : .failed
        case let .cmux(workspace, surface, socket):
            var args = ["focus-panel", "--panel", surface]
            if let workspace { args += ["--workspace", workspace] }
            let env = socket.map { ["CMUX_SOCKET_PATH": $0] } ?? [:]
            return Tools.run(Tools.cmux, args, environment: env) != nil ? .focused : .failed
        case let .terminalTab(app, source):
            guard let tty = resolve(source) else { return .failed }
            return TerminalScripts.select(app, tty: tty) ? .done : .failed
        case let .window(hints):
            return raiseWindow(host: host, hints: hints) ? .focused : .failed
        case .activate:
            DispatchQueue.main.async { HostActivator.activate(host) }
            return .done
        }
    }

    /// Opens a deep link in the host app itself, so another app claiming the scheme can't take it.
    private func openURL(_ string: String, host: HostInfo?) -> Bool {
        guard let url = URL(string: string) else { return false }
        let appURL = HostActivator.app(for: host)?.bundleURL
        let done = DispatchSemaphore(value: 0)
        var ok = false
        DispatchQueue.main.async {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            if let appURL {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { app, error in
                    ok = app != nil && error == nil
                    done.signal()
                }
            } else {
                ok = NSWorkspace.shared.open(url)
                done.signal()
            }
        }
        return done.wait(timeout: .now() + 5) == .success && ok
    }

    private func resolve(_ source: TTYSource) -> String? {
        switch source {
        case let .device(tty):
            return tty
        case let .tmuxClient(socket, pane):
            let base = socket.map { ["-S", $0] } ?? []
            let out = Tools.run(Tools.tmux, base + ["display-message", "-p", "-t", pane, "#{client_tty}"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let out, out.range(of: "\\A/dev/ttys?[0-9]{1,4}\\z", options: .regularExpression) != nil else { return nil }
            return out
        }
    }

    /// Raises the host app's window whose title names the project. Needs Accessibility access.
    private func raiseWindow(host: HostInfo?, hints: [String]) -> Bool {
        guard AXIsProcessTrusted(), let app = HostActivator.app(for: host) else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return false }
        let titled: [(AXUIElement, String)] = windows.compactMap { w in
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &title) == .success,
                  let s = title as? String else { return nil }
            return (w, s)
        }
        for hint in hints {
            guard let (window, _) = titled.first(where: { $0.1.localizedCaseInsensitiveContains(hint) }) else { continue }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            return true
        }
        return false
    }
}

/// Selects a terminal tab by its tty. The tty is passed as an argument, never spliced into the script.
enum TerminalScripts {
    private static let terminal = """
    on run argv
        set target to item 1 of argv
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is target then
                        set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "true"
                    end if
                end repeat
            end repeat
        end tell
        return "false"
    end run
    """

    private static let iterm = """
    on run argv
        set target to item 1 of argv
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is target then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return "true"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "false"
    end run
    """

    static func select(_ app: TerminalApp, tty: String) -> Bool {
        let bundleId = app == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2"
        // Never launch a terminal just to look for a tab.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else { return false }
        let script = app == .terminal ? terminal : iterm
        return Tools.run("/usr/bin/osascript", ["-e", script, tty], timeout: 10)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}

/// Runs helper command-line tools with a timeout.
enum Tools {
    static let tmux = firstExecutable(["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux",
                                        "/run/current-system/sw/bin/tmux"])
    static let cmux = firstExecutable(["/Applications/cmux.app/Contents/Resources/bin/cmux", "/opt/homebrew/bin/cmux",
                                        "/usr/local/bin/cmux"])

    private static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Standard output on exit status 0; nil on failure, timeout or a missing tool.
    static func run(_ path: String?, _ args: [String], environment: [String: String] = [:],
                    timeout: TimeInterval = 3) -> String? {
        guard let path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
