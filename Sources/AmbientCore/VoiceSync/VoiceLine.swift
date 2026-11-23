import Foundation
import AmbientBase
import AmbientContracts

/// One line of a voice, or a whole typed note, in the sender's outbox, which `follow` streams to the hub it's addressed to. Like a `RemoteEvent`,
/// it can't ask the hub to do anything: the most it can become is a recording in the voice library.
public struct VoiceLine: Equatable, Sendable {
    public enum Part: Equatable, Sendable {
        /// Recording began, by the sender's clock.
        case start(at: Date)
        /// Chunk `n` of the audio: whole ADTS frames.
        case audio(n: Int, data: Data)
        /// The whole transcript so far, which replaces the one before.
        case text(String)
        /// Recording ended, with the final transcript when there is one.
        case end(text: String?)
        case cancel
        /// A typed note, whole on one line: when it was written, by the sender's clock, and what it says.
        case note(at: Date, text: String)

        var name: String {
            switch self {
            case .start: "start"
            case .audio: "audio"
            case .text: "text"
            case .end: "end"
            case .cancel: "cancel"
            case .note: "note"
            }
        }
    }

    /// Characters of transcript a voice may carry: about ten minutes of speech.
    public static let maxText = 10_000
    /// Base64 characters in one chunk: 36 KB of audio, many times what half a second takes.
    public static let maxData = 48 * 1024
    public static let maxChunk = 100_000

    public let v: Int
    /// The outbox's own order.
    public let vseq: Int64
    /// The hub this voice is for.
    public let to: String
    public let voice: String
    public let part: Part

    public init(v: Int = RemoteEvent.currentVersion, vseq: Int64, to: String, voice: String, part: Part) {
        self.v = v
        self.vseq = vseq
        self.to = to
        self.voice = voice
        self.part = part
    }

    /// The line as the outbox holds it, without its newline. The fields up to `to` come first and in this order, since
    /// that's what `follow` matches to pick a hub's lines.
    public func encoded() -> Data {
        var s = #"{"v":\#(v),"type":"voice","vseq":\#(vseq),"to":"\#(to)","voice":"\#(voice)","part":"\#(part.name)""#
        switch part {
        case let .start(at):
            s += #","ts":\#(Int64(at.timeIntervalSince1970))"#
        case let .audio(n, data):
            s += #","n":\#(n),"data":"\#(data.base64EncodedString())""#
        case let .text(text):
            s += #","text":"# + JSONValue.string(text).serialized()
        case let .end(text):
            if let text { s += #","text":"# + JSONValue.string(text).serialized() }
        case .cancel:
            break
        case let .note(at, text):
            s += #","ts":\#(Int64(at.timeIntervalSince1970)),"text":"# + JSONValue.string(text).serialized()
        }
        return Data((s + "}").utf8)
    }

    /// A transcript the sender may put on a line: under `maxText` characters and well under the line cap however it's
    /// written.
    public static func cap(_ text: String) -> String {
        var cut = Trim.truncate(text, max: maxText)
        while cut.utf8.count > 40_000 { cut.removeLast(max(1, cut.count / 10)) }
        return cut
    }

    /// A note as it may go on a line, or arrive from one: plain text, as `Trim.plainText` leaves it, except that its line
    /// breaks, tabs and indentation stay, since a note is often a command or a list. Lines end in no spaces, there are no
    /// blank lines before or after it, never more than one blank line in a row, and it's under `maxText` characters and
    /// well under the line cap. Nil when nothing's left to read.
    public static func noteText(_ text: String) -> String? {
        let kept = text.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                return scalar == "\t" || scalar == "\n"
            default:
                return true
            }
        }
        var thin = String.UnicodeScalarView()
        for character in String(String.UnicodeScalarView(kept)) {
            thin.append(contentsOf: character.unicodeScalars.prefix(Trim.maxScalarsPerCharacter))
        }
        var lines: [Substring] = []
        for line in String(thin).split(separator: "\n", omittingEmptySubsequences: false) {
            var line = line
            while let last = line.last, last.isWhitespace { line.removeLast() }
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        var note = lines.joined(separator: "\n")
        guard !note.isEmpty else { return nil }
        if note.count > maxText { note = String(note.prefix(maxText - 1)) + "…" }
        while note.utf8.count > 40_000 { note.removeLast(max(1, note.count / 10)) }
        return note
    }

    static func isID(_ s: String) -> Bool {
        s.range(of: #"\A[0-9a-f]{32}\z"#, options: .regularExpression) != nil
    }
}

/// The strict decoder for voice lines: the fields each part allows and no others, ids as 32 lowercase hex, audio that's
/// base64 of well-formed ADTS, and a plain-text transcript under its cap. Anything else rejects the line.
enum VoiceLineDecoder {
    static let common: Set<String> = ["v", "type", "vseq", "to", "voice", "part"]
    static let extra: [String: Set<String>] = [
        "start": ["ts"], "audio": ["n", "data"], "text": ["text"], "end": ["text"], "cancel": [], "note": ["ts", "text"],
    ]

    static func line(from members: [JSONValue.Member]) throws(RemoteRejection) -> VoiceLine {
        let fields = try RemoteEventDecoder.flatFields(members, allowed: common.union(["ts", "n", "data", "text"]))
        for key in ["v", "vseq", "to", "voice", "part"] where fields[key] == nil || fields[key] == .null {
            throw .missingField(key)
        }
        let v = try RemoteEventDecoder.integer(fields, "v", in: 0...Int64(Int32.max))
        guard RemoteEvent.supportedVersions.contains(Int(v)) else { throw .unsupportedVersion(Int(v)) }
        let vseq = try RemoteEventDecoder.integer(fields, "vseq", in: 1...(1 << 53))
        guard let to = try RemoteEventDecoder.string(fields, "to"), VoiceLine.isID(to) else { throw .invalid("to") }
        guard let voice = try RemoteEventDecoder.string(fields, "voice"), VoiceLine.isID(voice) else { throw .invalid("voice") }
        guard let name = try RemoteEventDecoder.string(fields, "part"), let allowed = extra[name] else { throw .invalid("part") }
        if let stray = fields.keys.first(where: { !common.contains($0) && !allowed.contains($0) }) { throw .invalid(stray) }

        let part: VoiceLine.Part
        switch name {
        case "start":
            guard fields["ts"] != nil else { throw .missingField("ts") }
            part = .start(at: try RemoteEventDecoder.timestamp(fields))
        case "audio":
            let n = try RemoteEventDecoder.integer(fields, "n", in: 0...Int64(VoiceLine.maxChunk))
            guard let base64 = try RemoteEventDecoder.string(fields, "data") else { throw .missingField("data") }
            guard base64.utf8.count <= VoiceLine.maxData, let data = Data(base64Encoded: base64),
                  ADTS.frames(in: data) != nil else { throw .invalid("data") }
            part = .audio(n: Int(n), data: data)
        case "text":
            guard let text = try RemoteEventDecoder.string(fields, "text") else { throw .missingField("text") }
            part = .text(Trim.plainText(text, max: VoiceLine.maxText) ?? "")
        case "end":
            part = .end(text: try RemoteEventDecoder.string(fields, "text").map { Trim.plainText($0, max: VoiceLine.maxText) ?? "" })
        case "note":
            guard fields["ts"] != nil else { throw .missingField("ts") }
            guard let text = try RemoteEventDecoder.string(fields, "text") else { throw .missingField("text") }
            // A note with nothing left to read isn't one.
            guard let plain = VoiceLine.noteText(text) else { throw .invalid("text") }
            part = .note(at: try RemoteEventDecoder.timestamp(fields), text: plain)
        default:
            part = .cancel
        }
        return VoiceLine(v: Int(v), vseq: vseq, to: to, voice: voice, part: part)
    }
}
