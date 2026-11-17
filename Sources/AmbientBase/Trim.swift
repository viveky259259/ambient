import Foundation

/// Helpers for the short strings Ambient shows and sends.
public enum Trim {
    /// Collapses runs of whitespace into single spaces, trims, and cuts to `max` characters
    /// (grapheme clusters), ending with "…" when cut.
    public static func truncate(_ s: String, max: Int) -> String {
        let collapsed = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > max else { return collapsed }
        guard max > 1 else { return String(collapsed.prefix(max)) }
        return String(collapsed.prefix(max - 1)) + "…"
    }

    /// `truncate`, but nil for missing or blank input.
    public static func clean(_ s: String?, max: Int) -> String? {
        guard let s else { return nil }
        let out = truncate(s, max: max)
        return out.isEmpty ? nil : out
    }

    /// The most Unicode scalars `plainText` leaves on one character, since `truncate` counts characters and combining
    /// marks pile onto one without limit. Real text has room: a flag takes 2, a Thai syllable 3 or 4, the longest
    /// Sanskrit conjuncts about 10.
    public static let maxScalarsPerCharacter = 16

    /// Plain text only, for text from outside this Mac: control, format (including bidirectional overrides and
    /// zero-width characters) and line separator characters are removed, whitespace collapsed, the result cut to
    /// `max`, and no character left holding more than `maxScalarsPerCharacter`.
    public static func plainText(_ s: String, max: Int) -> String? {
        let kept = s.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                // Tabs and newlines become the spaces `truncate` collapses them into.
                return scalar == "\t" || scalar == "\n"
            default:
                return true
            }
        }
        return clean(String(String.UnicodeScalarView(kept)), max: max).map { text in
            var thin = String.UnicodeScalarView()
            for character in text { thin.append(contentsOf: character.unicodeScalars.prefix(maxScalarsPerCharacter)) }
            return String(thin)
        }
    }
}
