import Testing
@testable import AmbientCore

@Suite struct SpeechTextTests {
    @Test func headingsAndListsBecomeSentences() {
        let md = "# Summary\n\n- Fixed the **flaky** test\n- Added `retry()`\n1. Ran it\n- [x] Checked"
        #expect(SpeechText.spoken(md) == "Summary.\nFixed the flaky test.\nAdded retry().\nRan it.\nChecked.")
    }

    @Test func headingKeepsItsOwnPunctuation() {
        #expect(SpeechText.spoken("## Done!") == "Done!")
    }

    @Test func linksReadTheirLabelAndBareURLsTheirHost() {
        let md = "See [the docs](https://x.dev/a) and https://github.com/foo/bar."
        #expect(SpeechText.spoken(md) == "See the docs and github.com.")
    }

    @Test func codeBlocksAreSummarized() {
        let md = "Run this:\n```swift\nlet a = 1\nlet b = 2\n```\nDone"
        #expect(SpeechText.spoken(md) == "Run this:\nCode block, 2 lines.\nDone")
    }

    @Test func codeBlocksCanBeReadOut() {
        let md = "Run this:\n```swift\nlet a = 1\nlet b = 2\n```\nDone"
        #expect(SpeechText.spoken(md, readCode: true) == "Run this:\nlet a = 1\nlet b = 2\nDone")
    }

    @Test func unclosedFenceStillCounts() {
        #expect(SpeechText.spoken("```\nx = 1") == "Code block, 1 line.")
    }

    @Test func tablesReadRowByRow() {
        let md = "| File | Change |\n|---|---|\n| `a.swift` | **added** |"
        #expect(SpeechText.spoken(md) == "File, Change.\na.swift, added.")
    }

    @Test func longPathsKeepTheirLastTwoParts() {
        #expect(SpeechText.spoken("Edited Sources/AmbientApp/Speech/SpeechPlayer.swift today")
                == "Edited Speech/SpeechPlayer.swift today")
        #expect(SpeechText.spoken("Wrote ~/.ambient/voice/kokoro-1") == "Wrote voice/kokoro-1")
        #expect(SpeechText.spoken("and/or") == "and/or")
    }

    @Test func emphasisMarkersGoButIdentifiersStay() {
        #expect(SpeechText.spoken("*really* important and snake_case_name, 2 * 3")
                == "really important and snake_case_name, 2 * 3")
    }

    @Test func emojiAreDropped() {
        #expect(SpeechText.spoken("Done ✅ 🎉 👩‍💻") == "Done")
    }

    @Test func rulesAndQuotes() {
        #expect(SpeechText.spoken("---\n> quoted") == "quoted.")
    }

    @Test func whitespaceOnlyIsEmpty() {
        #expect(SpeechText.spoken("   \n\t \n") == "")
        #expect(SpeechText.spoken("---\n***") == "")
    }
}
