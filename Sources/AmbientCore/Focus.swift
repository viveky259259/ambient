import Foundation

public enum TerminalApp: String, Codable, Sendable {
    case terminal, iterm
}

/// Which terminal device a tab is found by.
public enum TTYSource: Equatable, Sendable {
    case device(String)
    /// Inside tmux the agent's tty is the pane's; the tab shows the tmux client's, asked for at click time.
    case tmuxClient(socket: String?, pane: String)
}

/// One way of bringing the user back to a session, most precise first.
public enum FocusRoute: Equatable, Sendable {
    /// A deep link into the agent's own app (Claude desktop chat, Codex thread).
    case openURL(String)
    case tmuxPane(socket: String?, pane: String)
    case cmux(workspace: String?, surface: String, socket: String?)
    case terminalTab(TerminalApp, TTYSource)
    /// Raise the host app's window whose title contains one of these, in order.
    case window(titleHints: [String])
    /// Bring the host app forward.
    case activate
}

public enum FocusPlanner {
    static let claudeDesktop = "com.anthropic.claudefordesktop"
    static let codexApp = "com.openai.codex"

    /// Routes to try in order. Everything that reaches a script, command or URL is validated here.
    public static func routes(for s: Session, userHome: String = NSHomeDirectory()) -> [FocusRoute] {
        var routes: [FocusRoute] = []
        let host = s.host

        if host?.bundleId == claudeDesktop, let id = host?.hostSessionId, matches(id, "^local_[A-Za-z0-9-]{1,64}$") {
            routes.append(.openURL("claude://code/continue?session=\(id)&source=ambient"))
        }
        if host?.bundleId == codexApp, s.agent == .codex, matches(s.sessionId, "^[A-Za-z0-9-]{1,64}$") {
            routes.append(.openURL("codex://threads/\(s.sessionId)"))
        }

        let tmuxPane = host?.tmuxPane.flatMap { matches($0, "^%[0-9]{1,6}$") ? $0 : nil }
        let tmuxSocket = host?.tmuxSocket.flatMap(safePath)
        if let tmuxPane { routes.append(.tmuxPane(socket: tmuxSocket, pane: tmuxPane)) }

        if let surface = host?.cmuxSurface, matches(surface, idPattern) {
            let workspace = host?.cmuxWorkspace.flatMap { matches($0, idPattern) ? $0 : nil }
            routes.append(.cmux(workspace: workspace, surface: surface, socket: host?.cmuxSocket.flatMap(safePath)))
        }

        if let app = terminalApp(host) {
            if let tmuxPane {
                routes.append(.terminalTab(app, .tmuxClient(socket: tmuxSocket, pane: tmuxPane)))
            } else if let tty = host?.tty, matches(tty, "^/dev/ttys?[0-9]{1,4}$") {
                routes.append(.terminalTab(app, .device(tty)))
            }
        }

        let hints = titleHints(cwd: s.cwd, userHome: userHome)
        if !hints.isEmpty, host?.bundleId != claudeDesktop, !(host?.bundleId == codexApp && s.agent == .codex) {
            routes.append(.window(titleHints: hints))
        }
        routes.append(.activate)
        return routes
    }

    private static let idPattern = "^[A-Za-z0-9_:-]{1,128}$"

    private static func terminalApp(_ host: HostInfo?) -> TerminalApp? {
        switch (host?.bundleId, host?.termProgram) {
        case ("com.apple.Terminal", _), (nil, "Apple_Terminal"): .terminal
        case ("com.googlecode.iterm2", _), (nil, "iTerm.app"): .iterm
        default: nil
        }
    }

    /// The project folder and its parent, stopping at the home directory.
    static func titleHints(cwd: String?, userHome: String) -> [String] {
        guard let cwd, cwd.hasPrefix("/") else { return [] }
        let home = userHome.hasSuffix("/") ? String(userHome.dropLast()) : userHome
        var parts = cwd.split(separator: "/").map(String.init)
        if cwd == home || cwd.hasPrefix(home + "/") {
            parts = Array(parts.dropFirst(home.split(separator: "/").count))
        }
        return Array(parts.reversed().prefix(2))
    }

    private static func safePath(_ path: String) -> String? {
        matches(path, "^/[A-Za-z0-9._/ -]{1,200}$") ? path : nil
    }

    /// Whole-string match. Patterns are written with ^…$, which ICU would let end before a final newline.
    private static func matches(_ s: String, _ pattern: String) -> Bool {
        let strict = "\\A" + pattern.dropFirst().dropLast() + "\\z"
        return s.range(of: strict, options: .regularExpression) != nil
    }
}

/// Finds the session a user means by `ambient open <query>`.
public enum SessionMatcher {
    /// `sessions` must be sorted most urgent first, as `SessionStore.sessions` is.
    public static func find(_ query: String?, in sessions: [Session]) -> Session? {
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            return IslandPolicy.primary(sessions) ?? sessions.first
        }
        if let s = sessions.first(where: { $0.project?.caseInsensitiveCompare(query) == .orderedSame }) { return s }
        if let s = sessions.first(where: { $0.id == query || $0.sessionId == query }) { return s }
        return sessions.first { $0.sessionId.hasPrefix(query) }
    }
}
