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
