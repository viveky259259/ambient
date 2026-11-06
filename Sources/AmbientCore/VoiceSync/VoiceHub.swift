import Foundation

extension AmbientPaths {
    /// Voice sync's own folder: the library, its audio and this Mac's hub id. Not `voice`, which holds the offline voice
    /// packs for reading aloud.
    public var voiceSync: URL { home.appendingPathComponent("voice-sync", isDirectory: true) }
    public var voiceLibrary: URL { voiceSync.appendingPathComponent("library.json") }
    public var voiceAudio: URL { voiceSync.appendingPathComponent("audio", isDirectory: true) }
    public var voiceHubID: URL { voiceSync.appendingPathComponent("hub.id") }
    /// Where the shim looks, which is always in the user's home, whatever `AMBIENT_HOME` says.
    public var voiceOutbox: URL { userHome.appendingPathComponent(".ambient/voice-sync", isDirectory: true) }
    public var voiceHubsSeen: URL { userHome.appendingPathComponent(".ambient/spool/hubs", isDirectory: true) }
}

/// This Mac as a destination for voices: a random id, made once, and the computer's name, which the sender shows.
public struct VoiceHub: Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = Self.label(label)
    }

    /// The saved id, or a new one saved for next time.
    public static func load(_ paths: AmbientPaths, name: String) -> VoiceHub {
        let url = paths.voiceHubID
        if let saved = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           VoiceLine.isID(saved) {
            return VoiceHub(id: saved, label: name)
        }
        let id = randomID()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if (try? Data((id + "\n").utf8).write(to: url, options: .atomic)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return VoiceHub(id: id, label: name)
    }

    /// What the hub may call itself on the command line: ASCII letters, digits, spaces, `.`, `_` and `-`, at most 40
    /// characters. The shim checks the same pattern. "Mac" when nothing is left.
    public static func label(_ name: String) -> String {
        let kept = name.unicodeScalars.filter { s in
            s.isASCII && (CharacterSet.alphanumerics.contains(s) || " ._-".unicodeScalars.contains(s))
        }
        let words = String(String.UnicodeScalarView(kept)).split(separator: " ").joined(separator: " ")
        let cut = String(words.prefix(40)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? "Mac" : cut
    }

    public static func randomID() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

/// What a hub asks `follow` for: its voices, from where it got to.
public struct VoiceFollow: Equatable, Sendable {
    public let hub: VoiceHub
    public let since: Int64

    public init(hub: VoiceHub, since: Int64) {
        self.hub = hub
        self.since = since
    }

    /// The arguments for `follow`. The id is hex and the label checked, so neither can break the quoting. A shim from
    /// before 1.0.6 skips `--voice-epoch`, as it does any argument it doesn't know.
    var arguments: String {
        guard VoiceLine.isID(hub.id) else { return "" }
        return #" --hub \#(hub.id) --hub-label "\#(VoiceHub.label(hub.label))" --voice-since \#(max(0, since)) --voice-epoch"#
    }
}

/// A Mac this one can record voices for: one whose Ambient follows this Mac.
public struct VoiceDestination: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    /// When its link last said so. Refreshed with every heartbeat, every 15 s.
    public let lastSeen: Date

    public init(id: String, label: String, lastSeen: Date) {
        self.id = id
        self.label = label
        self.lastSeen = lastSeen
    }

    /// Connected now: a voice reaches it as it's recorded. Otherwise it waits in the outbox.
    public func isOnline(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSeen) < 45
    }

    /// Where a voice goes: `chosen` when it's listed; else, of those connected now, the same one every time, since each
    /// heartbeat reorders them; else the one seen most recently.
    public static func preferred(in destinations: [VoiceDestination], chosen: String?, now: Date = Date()) -> VoiceDestination? {
        if let match = destinations.first(where: { $0.id == chosen }) { return match }
        return destinations.filter { $0.isOnline(now: now) }.min { ($0.label, $0.id) < ($1.label, $1.id) } ?? destinations.first
    }

    /// The hubs `follow` has registered, most recently seen first. A file that isn't a hub's is skipped.
    public static func load(from dir: URL) -> [VoiceDestination] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter(VoiceLine.isID).compactMap { id in
            let url = dir.appendingPathComponent(id)
            guard let seen = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return VoiceDestination(id: id, label: VoiceHub.label(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                                    lastSeen: seen)
        }
        .sorted { $0.lastSeen > $1.lastSeen }
    }
}
