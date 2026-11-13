import Foundation

/// A voice's whole transcript, from the speech recognizer's results as they come.
///
/// Each result carries the transcript of the stretch being heard so far, often revised as more is heard. But after a
/// pause the on-device recognizer starts over: the next result holds only what came after it. Kept as it came, the
/// transcript would be only the last stretch, so a minute of speech arrived on the other Mac as its last few words.
/// This keeps each finished stretch and adds the next one after it.
///
/// A stretch is finished when the recognizer says so (`ended`), or when a result starts over: it's less than half as
/// long as the one before, or no longer and with another first word. A revision grows, or changes a word or some
/// punctuation; it doesn't do either. A new stretch that begins with the same word, and isn't short, can still pass for
/// a revision, so `ended` is the better signal where there is one. A recognizer that marks every result ended can't
/// repeat itself here, because a stretch that only carries on the last one replaces it.
public struct TranscriptJoiner: Equatable, Sendable {
    private var finished: [String] = []
    private var current = ""

    public init() {}

    /// Everything heard so far, each stretch after the one before.
    public var text: String {
        (finished + [current]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A result: what the recognizer heard of the current stretch, and whether that stretch is over.
    public mutating func add(_ result: String, ended: Bool = false) {
        let heard = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heard.isEmpty {
            if current.isEmpty, let last = finished.last {
                // Right after a stretch ended: the same words again are that stretch sent twice, and more words after
                // them carry it on.
                if Self.key(heard) == Self.key(last) { return }
                if Self.begins(Self.key(heard), with: Self.key(last)) { finished.removeLast() }
            } else if !current.isEmpty, Self.startsOver(heard, after: current) {
                finish(current)
            }
            current = heard
        }
        if ended, !current.isEmpty {
            finish(current)
            current = ""
        }
    }

    /// Whether `words` starts with all of `start`'s words.
    private static func begins(_ words: String, with start: String) -> Bool {
        words == start || words.hasPrefix(start + " ")
    }

    /// A new stretch, not a revision of this one.
    private static func startsOver(_ heard: String, after previous: String) -> Bool {
        guard heard.count <= previous.count else { return false }
        return heard.count * 2 < previous.count || firstWord(heard) != firstWord(previous)
    }

    private static func firstWord(_ text: String) -> Substring? {
        key(text).split(separator: " ").first
    }

    /// Ends a stretch. One that carries on the last finished stretch replaces it, and one that's the same words adds
    /// nothing, so a stretch ended twice isn't kept twice.
    private mutating func finish(_ stretch: String) {
        if let last = finished.last, Self.begins(Self.key(stretch), with: Self.key(last)) {
            finished[finished.count - 1] = stretch
            return
        }
        finished.append(stretch)
    }

    /// Words only, lowercased: revisions change capitals and punctuation.
    private static func key(_ text: String) -> String {
        var words: [String] = []
        var word = ""
        for character in text.lowercased() {
            // Letters, numbers and the marks that join a script's letters, as in Devanagari.
            if character.isLetter || character.isNumber || character.unicodeScalars.allSatisfy({ $0.properties.isGraphemeExtend }) {
                word.append(character)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words.joined(separator: " ")
    }
}
