import Foundation

/// Opens a remote task's chat on the machine it runs on, by asking that machine's own Ambient: `ambient open <session>`
/// over the transport. That machine knows the chat's app, folder and window; none of it has to leave it.
///
/// This sends the machine a command, which the link never does. It adds no power: whoever holds the transport can run
/// anything there already. What needs care is that the session id came from that machine, so it's checked here before
/// it goes anywhere near a shell, and nothing that machine prints is shown.
public enum RemoteOpen {
    public enum Outcome: Equatable, Sendable {
        case opened
        /// The machine has the remote shim but no Ambient app, as on a devbox.
        case noApp
        /// Ambient is installed there but isn't running.
        case notRunning
        /// That machine has no session or saved chat by that id any more.
        case noSuchChat
        case unreachable
        case failed
    }

    /// `agent:session`, as the machine knows it, for one of its sessions: a hub's id with the `remote/<machine>/` cut off.
    /// Nil unless both parts are plain.
    public static func sessionID(agent: AgentKind, sessionId: String) -> String? {
        let id = "\(agent.rawValue):\(sessionId)"
        return isPlain(id) ? id : nil
    }

    private static func isPlain(_ id: String) -> Bool {
        id.range(of: #"\A[a-z]{1,16}:[A-Za-z0-9._-]{1,128}\z"#, options: .regularExpression) != nil
    }

    /// The command for the machine's login shell. `from` names this Mac in the notification shown there. It travels
    /// percent-encoded, so nothing in it can end a quote and "Advait's Mac Studio" arrives whole. An Ambient from before
    /// `--from` skips the flag and opens the chat anyway.
    public static func command(sessionID: String, from: String) -> String? {
        guard isPlain(sessionID) else { return nil }
        let flag = encodedName(from).map { #" "--from=\#($0)""# } ?? ""
        return #"sh -c '"$HOME/.ambient/bin/ambient" open \#(sessionID)\#(flag)'"#
    }

    /// The name as plain text of at most 48 characters, with everything but ASCII letters, digits and `-._` encoded.
    /// Nil when nothing is left.
    public static func encodedName(_ name: String) -> String? {
        guard let plain = RemoteEventDecoder.plainText(name, max: nameLimit) else { return nil }
        return plain.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    /// The asking Mac's name, as the receiving CLI reads it off `--from=`. A name that isn't valid percent-encoding is
    /// taken as it is. Either way it ends as plain text, since it came from another machine.
    public static func decodedName(_ flag: String) -> String? {
        RemoteEventDecoder.plainText(flag.removingPercentEncoding ?? flag, max: nameLimit)
    }

    static let nameLimit = 48
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")

    /// What happened, from the exit status and the CLI's own error lines. The text is matched, never shown.
    public static func outcome(_ result: RemoteTransport.Result) -> Outcome {
        if result.timedOut || result.status == 255 { return .unreachable }
        if result.status == 0 { return .opened }
        if result.status == 126 || result.status == 127 { return .noApp }
        if result.stderr.contains("isn't running") { return .notRunning }
        if result.stderr.contains("No session matches") { return .noSuchChat }
        return .failed
    }

    /// What the board says about it, with the machine's own label.
    public static func note(_ outcome: Outcome, machine: String) -> String {
        switch outcome {
        case .opened: "Opened on \(machine)"
        case .noApp: "\(machine) has no Ambient app to open it"
        case .notRunning: "Ambient isn't running on \(machine)"
        case .noSuchChat: "\(machine) no longer has this chat"
        case .unreachable: "Can't reach \(machine)"
        case .failed: "Couldn't open it on \(machine)"
        }
    }
}
