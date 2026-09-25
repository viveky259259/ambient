import Foundation

/// Helpers for the short strings Ambient shows and sends.
public enum Text {
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
}
