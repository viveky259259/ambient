import Foundation
import Testing
@testable import AmbientBase

@Suite struct TrimTests {
    @Test func shortTextIsUnchanged() {
        #expect(Trim.truncate("hello", max: 10) == "hello")
    }

    @Test func longTextIsCutWithEllipsis() {
        let out = Trim.truncate("abcdefghijklmnop", max: 8)
        #expect(out == "abcdefg…")
        #expect(out.count == 8)
    }

    @Test func whitespaceIsCollapsed() {
        #expect(Trim.truncate("  git   status\n\n --short \t", max: 80) == "git status --short")
    }

    @Test func emojiAreNotSplit() {
        let out = Trim.truncate("👩‍💻👩‍💻👩‍💻👩‍💻", max: 3)
        #expect(out == "👩‍💻👩‍💻…")
    }

    @Test func emptyOrBlankBecomesNil() {
        #expect(Trim.clean("   \n ", max: 10) == nil)
        #expect(Trim.clean(nil, max: 10) == nil)
        #expect(Trim.clean(" x ", max: 10) == "x")
    }
}
