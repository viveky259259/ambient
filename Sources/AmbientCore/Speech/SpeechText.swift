import Foundation

/// Turns an agent's markdown into text that reads well aloud, and splits it into chunks an engine can voice quickly.
public enum SpeechText {
    /// Markdown as you'd say it: no symbols, links by their label, code blocks summarized (or read out), tables row
    /// by row, long paths cut to their last two parts. Empty when there's nothing worth reading.
    public static func spoken(_ markdown: String, readCode: Bool = false) -> String {
        var out: [String] = []
        var fence: [String]?
        func closeFence(_ code: [String]) {
            if readCode {
                out.append(contentsOf: code.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            } else if !code.isEmpty {
                out.append("Code block, \(code.count) line\(code.count == 1 ? "" : "s").")
            }
        }
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let code = fence {
                    closeFence(code)
                    fence = nil
                } else {
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(raw)
                continue
            }
            if let s = spokenLine(line), !s.isEmpty { out.append(s) }
        }
        // A selection can end inside a code block.
        if let code = fence { closeFence(code) }
        return out.joined(separator: "\n")
    }

    static func spokenLine(_ line: String) -> String? {
        if line.isEmpty { return nil }
        if line.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil { return nil }
        if line.hasPrefix("|") {
            if line.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) != nil { return nil }
            let cells = line.split(separator: "|").map { inline(String($0)) }.filter { !$0.isEmpty }
            return sentence(cells.joined(separator: ", "))
        }
        var text = line
        for pattern in [#"^#{1,6}\s+"#, #"^>\s?"#, #"^[-*+]\s+(\[[ xX]\]\s+)?"#, #"^\d{1,3}[.)]\s+"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let spoken = inline(text)
        return text != line ? sentence(spoken) : spoken
    }

    /// Ends a heading, list item or table row with a full stop so the voice pauses.
    static func sentence(_ s: String) -> String {
        guard let last = s.last else { return "" }
        return ".!?:;…".contains(last) ? s : s + "."
    }

    static func inline(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<?https?://([^/\s>]+)[^\s>]*?>?(?=[.,;:!?)]*(?:\s|$))"#, with: "$1",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: #"(\*\*|__|~~)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<![\w*])[*_](?=\S)(.+?)(?<=\S)[*_](?![\w*])"#, with: "$1",
                                   options: .regularExpression)
        t = shortenPaths(t)
        t = String(String.UnicodeScalarView(t.unicodeScalars.filter {
            !$0.properties.isEmojiPresentation && $0 != "\u{FE0F}" && $0 != "\u{200D}"
        }))
        return t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Chunks of at most `limit` characters, split at sentence ends, then clauses, then words, and only as a last
    /// resort inside a run with no spaces (never inside a character). Short chunks let audio start quickly.
    public static func chunks(_ text: String, max limit: Int = 300) -> [String] {
        guard limit > 0 else { return [] }
        return pack(sentences(text).flatMap { fit($0, limit) }, limit)
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        func push() {
            let s = current.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { out.append(s) }
            current = ""
        }
        for (i, c) in chars.enumerated() {
            if c.isNewline {
                push()
                continue
            }
            current.append(c)
            if "。！？".contains(c) {
                push()
            } else if ".!?…".contains(c), i + 1 == chars.count || chars[i + 1].isWhitespace {
                push()
            }
        }
        push()
        return out
    }

    static func fit(_ s: String, _ limit: Int) -> [String] {
        guard s.count > limit else { return [s] }
        let clauses = split(s, after: ",;:")
        if clauses.count > 1 { return pack(clauses.flatMap { fit($0, limit) }, limit) }
        let words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1 { return pack(words.flatMap { fit($0, limit) }, limit) }
        var out: [String] = []
        var rest = Substring(s)
        while !rest.isEmpty {
            out.append(String(rest.prefix(limit)))
            rest = rest.dropFirst(limit)
        }
        return out
    }

    /// Splits after any of `marks` when whitespace follows; the mark stays with the text before it.
    static func split(_ s: String, after marks: String) -> [String] {
        var out: [String] = []
        var current = ""
        var afterMark = false
        func push() {
            let t = current.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
            current = ""
        }
        for c in s {
            if afterMark, c.isWhitespace {
                push()
                afterMark = false
                continue
            }
            current.append(c)
            afterMark = marks.contains(c)
        }
        push()
        return out
    }

    /// Joins pieces with spaces into runs of at most `limit` characters, never splitting a piece. Counts are kept
    /// rather than recomputed, since `String.count` walks the string.
    static func pack(_ pieces: [String], _ limit: Int) -> [String] {
        var out: [String] = []
        var current = ""
        var count = 0
        for piece in pieces {
            let n = piece.count
            if count == 0 {
                current = piece
                count = n
            } else if count + 1 + n <= limit {
                current += " " + piece
                count += 1 + n
            } else {
                out.append(current)
                current = piece
                count = n
            }
        }
        if count > 0 { out.append(current) }
        return out
    }

    /// `Sources/AmbientApp/Speech/SpeechPlayer.swift` → `Speech/SpeechPlayer.swift`. Needs two slashes, so
    /// "and/or" stays.
    static func shortenPaths(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\w/])[~.]{0,2}/?(?:[\w@.+-]+/){2,}[\w@.+-]+/?"#)
        else { return s }
        var out = s as NSString
        for m in regex.matches(in: s, range: NSRange(location: 0, length: out.length)).reversed() {
            let parts = out.substring(with: m.range).split(separator: "/").filter { !$0.isEmpty && $0 != "~" }
            out = out.replacingCharacters(in: m.range, with: parts.suffix(2).joined(separator: "/")) as NSString
        }
        return out as String
    }
}
