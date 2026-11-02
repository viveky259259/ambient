import CryptoKit
import Foundation

/// The `ambient-remote` shim that ships inside the signed app. It's the only source of the shim: it's copied from
/// here over the transport and never downloaded.
public struct RemoteShim: Sendable {
    public let bytes: Data
    public let sha256: String
    public let version: String

    public init(url: URL) throws {
        bytes = try Data(contentsOf: url)
        sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let text = String(decoding: bytes, as: UTF8.self)
        version = text.split(separator: "\n").first { $0.hasPrefix("AR_VERSION=") }.map { String($0.dropFirst("AR_VERSION=".count)) } ?? "unknown"
    }

    /// Inside the app, wherever the running tool sits in it: `Contents/Helpers/ambient` or `Contents/MacOS/Ambient`.
    /// `AMBIENT_REMOTE_SHIM` is for running outside a bundle, as `swift run` does.
    public static func bundledURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fm = FileManager.default
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let url = exe.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/ambient-remote")
            if fm.isReadableFile(atPath: url.path) { return url }
        }
        return environment["AMBIENT_REMOTE_SHIM"].map { URL(fileURLWithPath: $0) }.flatMap {
            fm.isReadableFile(atPath: $0.path) ? $0 : nil
        }
    }
}

/// Pairs a machine: copies the shim over the transport, checks its SHA-256 on the far side, runs its `install`, and
/// pins the identity it reports. Nothing is added to the allowlist until all of that has worked. A machine that's
/// already pinned says who it is first, so a different one is left as it was.
public enum RemotePairing {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case invalidID(String)
        case unreachable(String)
        case copyFailed(String)
        case checksumMismatch(expected: String, got: String)
        case installFailed(String)
        case badStatus(String)
        case identityChanged(expected: String, got: String)

        public var description: String {
            switch self {
            case let .invalidID(id):
                "'\(id)' isn't a valid machine name. Use lowercase letters, digits, '.', '_' and '-', at most 32 characters."
            case let .unreachable(reason):
                "Couldn't reach the machine: \(reason)"
            case let .copyFailed(reason):
                "Couldn't copy the shim: \(reason)"
            case let .checksumMismatch(expected, got):
                "The shim on the machine doesn't match the app's: expected \(expected), got \(got). Nothing was paired."
            case let .installFailed(reason):
                "The shim's install failed: \(reason)"
            case let .badStatus(reason):
                "The machine's status couldn't be read: \(reason)"
            case let .identityChanged(expected, got):
                "This machine's identity changed from \(expected) to \(got). If that's expected, add it again with --accept-new-identity."
            }
        }
    }

    public struct Request: Sendable {
        public var id: String
        public var label: String?
        public var transport: [String]
        public var redaction: RemoteRedaction?
        public var agents: [String]
        public var acceptNewIdentity: Bool

        public init(id: String, label: String? = nil, transport: [String], redaction: RemoteRedaction? = nil,
                    agents: [String] = [], acceptNewIdentity: Bool = false) {
            self.id = id
            self.label = label
            self.transport = transport
            self.redaction = redaction
            self.agents = agents
            self.acceptNewIdentity = acceptNewIdentity
        }
    }

    public struct Outcome: Sendable {
        public let machine: Machine
        public let status: RemoteStatus
        /// What the shim's `install` printed, as plain text. Comes from the machine, so it's been sanitized.
        public let installLines: [String]
        /// Python isn't on the machine and a config needs editing by hand; `installLines` says how.
        public let needsManualStep: Bool
    }

    public static func pair(_ request: Request, shim: RemoteShim, existing: Machine?, audit: RemoteAudit?) throws(Failure) -> Outcome {
        guard Machine.isValidID(request.id) else { throw .invalidID(request.id) }
        let transport = RemoteTransport(argv: request.transport)

        if existing != nil, !request.acceptNewIdentity {
            try requireIdentity(try identity(over: transport, shim: shim), request: request, existing: existing, audit: audit)
        }

        let copied = transport.run(RemoteTransport.copyShim, input: shim.bytes, timeout: 60)
        guard copied.ok else {
            if copied.status == 255 || copied.status == 127 || copied.timedOut { throw .unreachable(explain(copied)) }
            throw .copyFailed(explain(copied))
        }
        let hashed = transport.run(RemoteTransport.hashShim)
        guard hashed.ok, hashed.lastLineWord == shim.sha256 else {
            throw .checksumMismatch(expected: shim.sha256, got: hashed.lastLineWord)
        }

        var arguments = "install"
        if let redaction = request.redaction { arguments += " --redaction \(redaction.rawValue)" }
        let agents = request.agents.filter { ["claude", "codex"].contains($0) }
        if !agents.isEmpty { arguments += " --agents \(agents.joined(separator: ","))" }
        let installed = transport.run(RemoteTransport.shim(arguments), timeout: 60)
        guard installed.status == 0 || installed.status == 3 else { throw .installFailed(explain(installed)) }
        let lines = (installed.text + installed.stderr).split(whereSeparator: \.isNewline).compactMap {
            RemoteEventDecoder.plainText(String($0), max: 240)
        }

        let reported = transport.run(RemoteTransport.shim("status"))
        guard reported.ok else { throw .badStatus(explain(reported)) }
        let status: RemoteStatus
        do {
            status = try RemoteLineDecoder.status(reported.lastLine)
        } catch {
            throw .badStatus(error.description)
        }

        let identity = status.hello.identity
        try requireIdentity(identity, request: request, existing: existing, audit: audit)
        if let existing, existing.fingerprint != identity {
            audit?.append(.init(action: .fingerprintChanged, machine: request.id, detail: "approved \(identity)"))
        }
        audit?.append(.init(action: .paired, machine: request.id, detail: identity))
        // Always a new date: a changed machine is what restarts its link, so the new shim and level take effect.
        let machine = Machine(id: request.id, label: request.label ?? existing?.label, transport: request.transport,
                              fingerprint: identity)
        return Outcome(machine: machine, status: status, installLines: lines, needsManualStep: installed.status == 3)
    }

    /// What became of `ambient remote remove --uninstall`.
    public enum Uninstall: Equatable, Sendable {
        case removed
        /// Python isn't on the machine, so its hooks stay for the user to remove. They do nothing now.
        case needsManualStep
        /// The transport reaches another machine, which was left as it was. Holds what that one reports.
        case differentMachine(String)
        case failed(String)
    }

    /// Clears the hooks, spool and shim from a paired machine, once it has said it's that machine.
    public static func uninstall(_ machine: Machine, shim: RemoteShim) -> Uninstall {
        let transport = RemoteTransport(argv: machine.transport)
        let reported: String
        do {
            reported = try identity(over: transport, shim: shim)
        } catch {
            return .failed(error.description)
        }
        guard reported == machine.fingerprint else { return .differentMachine(reported) }
        let result = transport.run(RemoteTransport.shim("uninstall"), timeout: 60)
        if result.ok { return .removed }
        if result.status == 3 { return .needsManualStep }
        return .failed(result.timedOut ? "timed out" : "exit status \(result.status)")
    }

    /// Who a machine says it is, asked before anything there changes. This app's shim runs from stdin, so it doesn't
    /// matter what's installed there, if anything, and it leaves nothing behind.
    static func identity(over transport: RemoteTransport, shim: RemoteShim) throws(Failure) -> String {
        let reported = transport.run(RemoteTransport.identify, input: shim.bytes)
        guard reported.ok else { throw .unreachable(explain(reported)) }
        return Machine.isValidFingerprint(reported.lastLineWord) ? reported.lastLineWord : "no identity"
    }

    /// Stops at a machine other than the pinned one, unless the user has said that's expected.
    private static func requireIdentity(_ identity: String, request: Request, existing: Machine?, audit: RemoteAudit?) throws(Failure) {
        guard let existing, existing.fingerprint != identity, !request.acceptNewIdentity else { return }
        audit?.append(.init(action: .fingerprintChanged, machine: request.id, detail: identity))
        throw .identityChanged(expected: existing.fingerprint, got: identity)
    }

    static func explain(_ result: RemoteTransport.Result) -> String {
        if result.timedOut { return "timed out" }
        let lines = (result.stderr + "\n" + result.text).split(whereSeparator: \.isNewline)
        return RemoteEventDecoder.plainText(lines.last.map(String.init) ?? "", max: 200) ?? "exit status \(result.status)"
    }
}

/// `ambient doctor --remote`: what's true of one machine's link right now (ER-29).
public enum RemoteDoctor {
    public struct Check: Equatable, Sendable {
        public enum Level: Sendable { case ok, warn, fail }

        public let level: Level
        public let text: String

        public init(_ level: Level, _ text: String) {
            self.level = level
            self.text = text
        }
    }

    public static func check(_ machine: Machine, shim: RemoteShim?, cursor: RemoteCursor?) -> [Check] {
        let transport = RemoteTransport(argv: machine.transport)
        let reached = transport.run(#"sh -c 'echo ok'"#)
        guard reached.ok else {
            return [Check(.fail, "Transport can't reach \(machine.id): \(RemotePairing.explain(reached))")]
        }
        var checks = [Check(.ok, "Transport reaches \(machine.id)")]

        let reported = transport.run(RemoteTransport.shim("status"))
        guard reported.ok, let status = try? RemoteLineDecoder.status(reported.lastLine) else {
            checks.append(Check(.fail, "ambient-remote isn't working there: \(RemotePairing.explain(reported)). Run `ambient remote add \(machine.id)`."))
            return checks
        }

        if let shim {
            checks.append(status.hello.shim == shim.version
                ? Check(.ok, "Shim version \(status.hello.shim)")
                : Check(.warn, "Shim version \(status.hello.shim); this app has \(shim.version). Run `ambient remote add \(machine.id)`."))
            let hashed = transport.run(RemoteTransport.hashShim)
            checks.append(hashed.lastLineWord == shim.sha256
                ? Check(.ok, "Shim checksum matches the app's")
                : Check(status.hello.shim == shim.version ? .fail : .warn, "Shim checksum differs from the app's (\(String(hashed.lastLineWord.prefix(12)))…)"))
        } else {
            checks.append(Check(.warn, "This tool isn't in the app bundle, so the shim can't be compared with it"))
        }

        checks.append(status.hello.identity == machine.fingerprint
            ? Check(.ok, "Identity matches the pinned \(machine.fingerprint)")
            : Check(.fail, "Identity is \(status.hello.identity), but \(machine.fingerprint) is pinned. The link has stopped."))
        checks.append(status.spoolPermsOK
            ? Check(.ok, "Spool is private: \(ByteCountFormatter.string(fromByteCount: status.spoolBytes, countStyle: .file)), level \(status.hello.level.rawValue)")
            : Check(.fail, "Spool permissions are too open. They should be 0700 for folders and 0600 for files."))

        for (name, state) in [("Claude Code", status.claude), ("Codex", status.codex)] {
            switch state {
            case .installed: checks.append(Check(.ok, "\(name): hooks installed"))
            case .partial: checks.append(Check(.warn, "\(name): hooks are incomplete. Run `ambient remote add \(machine.id)`."))
            case .missing: checks.append(Check(.warn, "\(name): hooks not installed. Run `ambient remote add \(machine.id)`."))
            case .absent: checks.append(Check(.ok, "\(name): not on this machine"))
            }
        }

        if let cursor, cursor.epoch == status.hello.epoch {
            let lag = status.hello.seq - cursor.seq
            checks.append(lag <= 0
                ? Check(.ok, "Cursor is up to date at \(cursor.seq)")
                : Check(.warn, "Cursor is \(lag) event\(lag == 1 ? "" : "s") behind"))
        } else {
            checks.append(Check(.warn, "No events received from this spool yet"))
        }
        return checks
    }
}

/// Deletes what a machine left on the hub.
public enum RemotePurge {
    private static func tombstone(_ id: String, paths: AmbientPaths) -> URL {
        paths.remoteDir.appendingPathComponent("purged", isDirectory: true).appendingPathComponent(id)
    }

    /// Takes a machine's sessions and cursor out of the saved state.
    public static func removeSessions(machine id: String, paths: AmbientPaths) throws {
        var cursors = StateFile.loadCursors(from: paths.stateFile)
        let sessions = StateFile.load(from: paths.stateFile)
        let kept = sessions.filter { $0.origin?.machine.id != id }
        guard kept.count != sessions.count || cursors[id] != nil else { return }
        cursors[id] = nil
        try StateFile.save(kept, cursors: cursors, to: paths.stateFile)
    }

    /// Also takes it off the board and out of today's moments. A running app does the same to what it holds in
    /// memory when it next finds the marker left here, and clears it.
    public static func scrub(machine id: String, paths: AmbientPaths) throws {
        try removeSessions(machine: id, paths: paths)
        let tasks = TaskFile.load(from: paths.tasksFile)
        let kept = tasks.filter { $0.machine?.id != id }
        if kept.count != tasks.count { try TaskFile.save(kept, to: paths.tasksFile) }
        if var day = DayLogFile.load(from: paths.dayFile) {
            day.removeMoments(machine: id)
            try DayLogFile.save(day, to: paths.dayFile)
        }
        let marker = tombstone(id, paths: paths)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data().write(to: marker)
    }

    /// Machines purged since the app last looked. Ids are checked, so a stray file can't name anything else.
    public static func pendingPurges(paths: AmbientPaths) -> [String] {
        let dir = paths.remoteDir.appendingPathComponent("purged", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter(Machine.isValidID)
    }

    public static func clearPurge(_ id: String, paths: AmbientPaths) {
        try? FileManager.default.removeItem(at: tombstone(id, paths: paths))
    }
}
