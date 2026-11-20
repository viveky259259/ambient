import Foundation
import Testing
@testable import AmbientBase

@Suite("Trim.truncate")
struct QATrimTruncateTests {
    @Test(arguments: [
        ("", 10, ""),
        ("abc", 3, "abc"),            // exactly max: no ellipsis
        ("abcd", 3, "ab…"),
        ("abcd", 2, "a…"),
        ("abcd", 1, "a"),             // too short for an ellipsis
        ("abcd", 0, ""),
        ("   ", 5, ""),
        ("a\u{00A0}b", 10, "a b"),    // NBSP is whitespace
        ("a\u{2003}\u{3000}b", 10, "a b"),
        ("a\r\nb\u{2028}c\u{0085}d", 10, "a b c d"),
        ("x\u{200B}y", 10, "x\u{200B}y"), // zero-width space is not whitespace
    ])
    func cases(input: String, max: Int, expected: String) {
        #expect(Trim.truncate(input, max: max) == expected)
    }

    @Test func outputNeverExceedsMax() {
        let input = "The quick  brown\tfox jumps over the lazy dog 🦊🐶 é"
        for max in 0...60 {
            #expect(Trim.truncate(input, max: max).count <= max, "max \(max)")
        }
    }

    @Test func collapsingHappensBeforeCounting() {
        // 10 spaces between words would exceed max 5, but collapse to "a b".
        #expect(Trim.truncate("a          b", max: 5) == "a b")
    }

    @Test func truncationCanLeaveATrailingSpaceBeforeTheEllipsis() {
        #expect(Trim.truncate("ab cd", max: 4) == "ab …")
    }

    @Test func combiningMarksStayOnTheirCharacter() {
        let e = "e\u{0301}"
        #expect(Trim.truncate(String(repeating: e, count: 5), max: 3) == e + e + "…")
    }

    @Test func flagsAreNotSplit() {
        #expect(Trim.truncate("🇮🇳🇺🇸🇯🇵", max: 2) == "🇮🇳…")
    }

    @Test func negativeMaxIsSafe() async {
        await withKnownIssue("BUG: Trim.truncate traps (String.prefix with a negative length) when max < 0") {
            await #expect(processExitsWith: .success) {
                _ = Trim.truncate("abc", max: -1)
            }
        }
    }
}

@Suite("Trim.clean")
struct QATrimCleanTests {
    @Test func nilAndBlankAreNil() {
        #expect(Trim.clean(nil, max: 5) == nil)
        #expect(Trim.clean("", max: 5) == nil)
        #expect(Trim.clean(" \t\n\u{00A0}", max: 5) == nil)
    }

    @Test func maxZeroIsAlwaysNil() {
        #expect(Trim.clean("hello", max: 0) == nil)
    }

    @Test func otherwiseMatchesTruncate() {
        for s in ["a", "  hello   world ", "abcdefghijkl", "🚀🚀🚀🚀"] {
            #expect(Trim.clean(s, max: 5) == Trim.truncate(s, max: 5))
        }
    }
}

@Suite("Trim.plainText")
struct QATrimPlainTextTests {
    @Test func plainInputPassesThrough() {
        #expect(Trim.plainText("Hello, world! é 中文 🚀", max: 100) == "Hello, world! é 中文 🚀")
    }

    @Test func tabsAndNewlinesBecomeSpaces() {
        #expect(Trim.plainText("a\tb\nc\r\nd", max: 100) == "a b c d")
    }

    @Test(arguments: [
        "\u{0000}", "\u{0007}", "\u{001B}", "\u{007F}", "\u{0085}",   // C0/C1 controls
        "\u{200B}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202E}", "\u{2066}", "\u{2069}", "\u{FEFF}",  // format
        "\u{00AD}",                                                    // soft hyphen (format)
        "\u{2028}", "\u{2029}",                                        // line / paragraph separators
        "\u{E000}", "\u{F8FF}", "\u{F0000}",                           // private use
        "\u{0378}",                                                    // unassigned
    ])
    func dangerousScalarsAreRemoved(scalar: String) {
        #expect(Trim.plainText("ab\(scalar)cd", max: 100) == "abcd", "\(scalar.unicodeScalars.first!.value)")
    }

    @Test func bidiOverrideAttackIsNeutralised() {
        // "Trojan Source"-style reordering: the override must not survive.
        let out = Trim.plainText("access\u{202E} level\u{2066}admin", max: 100)
        #expect(out == "access leveladmin")
        #expect(out?.unicodeScalars.contains { $0.properties.generalCategory == .format } == false)
    }

    @Test func blankOrOnlyControlsIsNil() {
        #expect(Trim.plainText("", max: 10) == nil)
        #expect(Trim.plainText("   \t\n", max: 10) == nil)
        #expect(Trim.plainText("\u{0000}\u{200B}\u{202E}", max: 10) == nil)
    }

    @Test func cutsToMaxWithEllipsis() {
        #expect(Trim.plainText("abcdefghij", max: 5) == "abcd…")
        #expect(Trim.plainText("abc", max: 0) == nil)
    }

    @Test func removalHappensBeforeCounting() {
        let hidden = String(repeating: "\u{200B}", count: 50)
        #expect(Trim.plainText("ab\(hidden)cd", max: 4) == "abcd")
    }

    @Test func zalgoIsCappedPerCharacter() throws {
        let mark = "\u{0301}"
        let zalgo = "e" + String(repeating: mark, count: 200)
        let out = try #require(Trim.plainText(zalgo + " ok", max: 10))
        #expect(out.count == 4)  // one capped character + " ok"
        let first = try #require(out.first)
        #expect(first.unicodeScalars.count == Trim.maxScalarsPerCharacter)
        #expect(out.hasSuffix(" ok"))
    }

    @Test func charactersUnderTheCapAreUntouched() {
        let s = "e" + String(repeating: "\u{0301}", count: Trim.maxScalarsPerCharacter - 1)
        #expect(Trim.plainText(s, max: 10) == s)
    }

    @Test func maxScalarsPerCharacterValue() {
        #expect(Trim.maxScalarsPerCharacter == 16)
    }

    @Test func flagsAndSkinTonesSurvive() {
        #expect(Trim.plainText("🇮🇳 👍🏽", max: 10) == "🇮🇳 👍🏽")
    }

    @Test func variationSelectorsSurvive() {
        #expect(Trim.plainText("❤\u{FE0F}", max: 10) == "❤\u{FE0F}")
    }

    @Test func zeroWidthJoinerSequencesSurvive() {
        withKnownIssue("BUG: Trim.plainText strips U+200D ZWJ (category Cf), splitting emoji such as 👩‍💻 into 👩💻") {
            #expect(Trim.plainText("👩‍💻", max: 10) == "👩‍💻")
        }
    }

    @Test func zeroWidthNonJoinerInPersianSurvives() {
        // "می‌خواهم" (Persian, "I want") needs U+200C to render correctly.
        withKnownIssue("BUG: Trim.plainText strips U+200C ZWNJ, which Persian and Indic scripts need") {
            #expect(Trim.plainText("می\u{200C}خواهم", max: 20) == "می\u{200C}خواهم")
        }
    }

    @Test func carriageReturnSeparatesWords() {
        withKnownIssue("BUG: Trim.plainText deletes a lone \\r (and VT/FF/NEL) instead of treating it as whitespace, so \"a\\rb\" becomes \"ab\"") {
            #expect(Trim.plainText("one\rtwo", max: 20) == "one two")
        }
    }

    @Test func resultIsWithinMax() {
        let messy = "  \u{202E}hello\u{0000}\tworld \u{200B}" + String(repeating: "x\u{0301}\u{0302}", count: 50)
        for max in 1...40 {
            #expect((Trim.plainText(messy, max: max)?.count ?? 0) <= max)
        }
    }
}
