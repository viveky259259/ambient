# Speak Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select text in Claude, Codex or a terminal, press one shortcut, and Ambient reads it aloud with a Mac voice, an offline Kokoro model, or an online voice.

**Architecture:** Pure, tested logic lives in `AmbientCore/Speech` (markdown-to-speech, chunking, the chunk pipeline, the helper wire format, online request building, the voice pack manifest). The app adds a Services provider (and, if the probe says so, a hotkey with an Accessibility reader), three `SpeechEngine`s feeding one `SpeechPlayer`, a `SpeechController` whose state the island, menu bar and pet show, a first-run chooser and Settings › Voice. Kokoro runs in a separate `ambient-voice` helper package (`Voice/`) downloaded on demand, so Ambient keeps zero dependencies.

**Tech Stack:** Swift 6 (Core, Swift Testing), AppKit/SwiftUI (app, Swift 5 mode), AVFoundation, Security, CryptoKit, Carbon hotkeys, kokoro-ios 1.0.11 + MisakiSwift + MLX Swift 0.30.2 (helper only), xcodebuild.

**Spec:** `docs/superpowers/specs/2026-10-12-speak-selection-design.md`

## Global Constraints

- Ambient's own `Package.swift` gains no dependencies. Only `Voice/Package.swift` depends on kokoro-ios.
- Ambient still runs on macOS 14 (Intel and Apple Silicon). The offline model needs macOS 15 and Apple Silicon; elsewhere it shows as unavailable with the reason.
- Core code builds in Swift 6 language mode; the app target stays in Swift 5 mode.
- API keys live only in the Keychain, service `com.viveky259259.Ambient.voice`, account = `OnlineProvider.rawValue`.
- Ambient never switches engines on its own. Every failure is shown; the user picks the fallback.
- Chunks are at most 300 characters. Online requests time out after 15 s. The helper exits after 5 idle minutes.
- Nothing lands in `~/.ambient/voice` unless every SHA-256 matched and the helper's signature belongs to team `CU3457GT8T`.
- Kokoro files come from `huggingface.co/prince-canuma/Kokoro-82M` at commit `e02c9eada7ce7416798af36b190a8a2dd2ecd566`.
- User-facing copy, verbatim: "Select some text first", "This app needs Accessibility to read selections — Settings › Voice", "Offline voice stopped", "Use Mac voice", "Speak with Ambient", "Download (≈N MB)" with N computed from the manifest.
- Follow the repo's conventions in `CONTRIBUTING.md`: logic in Core with tests, the app renders decisions. Run `swift test` before each commit.
- This checkout is shared with another session. Work only in `.claude/worktrees/speak-selection` on `feat/speak-selection`.

## Review Focus

1. **Shortcut pressed again while the next chunk is still being synthesized**: stopping or restarting must never let old audio play after the new job starts. Pinned by `SpeechPipelineTests.cancelDuringPlayStopsEverything` (Task 4) and the job token in `SpeechPlayer` (Task 8).
2. **A selection that is only whitespace, or only symbols**: treated as "Select some text first", never as an empty request to an engine. Pinned by `SpeechTextTests.whitespaceOnlyIsEmpty` (Task 2).
3. **A huge selection (a whole transcript, 200k characters)**: chunking must stay fast enough that audio starts within about a second. Pinned by `SpeechChunkTests.hugeSelectionIsFast` (Task 3).
4. **Text with no spaces or sentence marks (CJK, a long URL) and emoji sequences**: chunks still respect the limit and never split a character. Pinned by `SpeechChunkTests.cjkWithoutPunctuation` and `emojiAreNeverSplit` (Task 3).
5. **The helper dies mid-answer or writes garbage**: Ambient reports "Offline voice stopped" rather than hanging or playing noise. Pinned by `VoiceWireTests.truncatedFrameWaits`, `oversizedFrameThrows` and `malformedHeaderThrows` (Task 5), and the EOF handling in `KokoroVoice` (Task 13).

---

### Task 1: Probe — Services shortcut and Accessibility in the four host apps

This decides the trigger route. The Services provider written here is kept.

**Files:**
- Create: `Sources/AmbientApp/Speech/SelectionService.swift`
- Modify: `Resources/Info.plist` (add `NSServices`)
- Modify: `Sources/AmbientApp/AppDelegate.swift` (register the provider)
- Modify: `docs/superpowers/specs/2026-10-12-speak-selection-design.md` (record results)

**Interfaces:**
- Produces: `final class SelectionService: NSObject` with `init(onText: @escaping (String?) -> Void)` and `func register()`.

- [ ] **Step 1: Write the Services provider**

```swift
import AppKit
import os

/// "Speak with Ambient" in every app's Services menu, and the shortcut macOS gives it. macOS hands us the
/// selection on a pasteboard, so this route needs no Accessibility permission.
final class SelectionService: NSObject {
    private let onText: (String?) -> Void

    init(onText: @escaping (String?) -> Void) {
        self.onText = onText
    }

    func register() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Named by `NSMessage` in Info.plist.
    @objc func speakWithAmbient(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .string)
        DispatchQueue.main.async { self.onText(text) }
    }
}
```

- [ ] **Step 2: Declare the service in `Resources/Info.plist`**

Add inside the top-level `<dict>`, after `NSCalendarsUsageDescription`:

```xml
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Speak with Ambient</string>
			</dict>
			<key>NSMessage</key>
			<string>speakWithAmbient</string>
			<key>NSPortName</key>
			<string>Ambient</string>
			<key>NSSendTypes</key>
			<array>
				<string>NSStringPboardType</string>
				<string>public.utf8-plain-text</string>
			</array>
			<key>NSRequiredContext</key>
			<dict/>
			<key>NSKeyEquivalent</key>
			<dict>
				<key>default</key>
				<string>U</string>
			</dict>
		</dict>
	</array>
```

An uppercase letter means ⌘⇧ plus that letter (⌘⇧U). `NSRequiredContext` turns the service on by default.

- [ ] **Step 3: Register it with a probe handler**

In `AppDelegate`, add `private var selectionService: SelectionService?` beside the other controllers, and at the end of `applicationDidFinishLaunching` (before the `setupCompleted` check):

```swift
        let selectionService = SelectionService { [weak self] text in
            self?.log.notice("Speak with Ambient: \(text?.count ?? -1, privacy: .public) characters")
            NSSound(named: "Tink")?.play()
        }
        selectionService.register()
        self.selectionService = selectionService
```

- [ ] **Step 4: Build and run a dev build**

Run: `scripts/build-app.sh --run`
Expected: `Built build/Ambient.app (...)`. The script quits the running Ambient (including `/Applications/Ambient.app`, since only one instance runs) and opens the dev build.

Then refresh the Services registry:

Run: `/System/Library/CoreServices/pbs -update && /System/Library/CoreServices/pbs -dump_pboard 2>/dev/null | grep -c "Speak with Ambient" || /System/Library/CoreServices/pbs -dump | grep -c "Speak with Ambient"`
Expected: a count of at least 1.

- [ ] **Step 5: Check that ⌘⇧U is free in each host app**

Run, for each app that is running (`Claude`, `Codex`, `Terminal`, `iTerm2`):

```bash
osascript -e 'tell application "System Events" to tell process "Claude" to get {name, AXMenuItemCmdChar, AXMenuItemCmdModifiers} of every menu item of every menu of every menu bar item of menu bar 1' 2>/dev/null | tr ',' '\n' | grep -n '^ *U$'
```

Expected: no output. Any hit means ⌘⇧U or ⌘U may be taken. Check that the modifiers next to it include Shift (`1` means ⌘⇧). If ⌘⇧U is taken in any app, repeat with `J`, then `K`, and use the first free letter in Step 2.

- [ ] **Step 6: Run the probe matrix by hand**

In each of Claude desktop (a Code chat), the Codex app (a thread), Terminal and iTerm2: select part of an agent reply and

1. open the app's own menu › Services: is **Speak with Ambient** listed?
2. press ⌘⇧U: do you hear the Tink, and does `log show --last 1m --predicate 'subsystem == "com.viveky259259.Ambient"' | grep "Speak with Ambient"` show a non-zero character count matching the selection?
3. repeat 2 while the agent is streaming a reply.
4. right-click the selection: is there a Services submenu with the item?

- [ ] **Step 7: Probe Accessibility selection in the two Electron apps**

Save as `$TMPDIR/ax-probe.swift` (scratch, not committed):

```swift
import AppKit
import ApplicationServices

// Waits 5 s so you can switch to the target app with text selected, then prints AXSelectedText.
sleep(5)
guard let app = NSWorkspace.shared.frontmostApplication else { exit(1) }
let appElement = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
usleep(300_000)
var focused: CFTypeRef?
let r1 = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
var text: CFTypeRef?
let r2 = focused.map { AXUIElementCopyAttributeValue($0 as! AXUIElement, kAXSelectedTextAttribute as CFString, &text) }
print(app.localizedName ?? "?", r1.rawValue, r2?.rawValue ?? -1, (text as? String)?.prefix(80) ?? "nil")
```

Run: `swift $TMPDIR/ax-probe.swift`, switch to Claude with text selected, then again for Codex.
Expected: `Claude 0 0 <the selection>`. The terminal app running this needs Accessibility (System Settings › Privacy & Security › Accessibility). Record whatever it prints.

- [ ] **Step 8: Record the results and the decision in the spec**

Append to the spec:

```markdown
## Probe results (2026-10-12)

| App | Listed in app menu › Services | ⌘⇧<key> delivers selection | Works while streaming | In right-click menu | AXSelectedText |
| --- | --- | --- | --- | --- | --- |
| Claude desktop | … | … | … | … | … |
| Codex app | … | … | … | … | n/a |
| Terminal | … | … | … | … | n/a |
| iTerm2 | … | … | … | … | n/a |

Decision: <Services route — the shortcut is ⌘⇧<key>, Task 9 is skipped> or <Hotkey route — ⌃⌥⌘S with Accessibility, Task 9 is required>.
```

Fill every cell with yes or no from Steps 6 and 7. **Services route** only if column 3 is "yes" for all four apps.

- [ ] **Step 9: Commit**

```bash
git add Sources/AmbientApp/Speech/SelectionService.swift Resources/Info.plist Sources/AmbientApp/AppDelegate.swift docs/superpowers/specs/2026-10-12-speak-selection-design.md
git commit -m "feat(speech): Speak with Ambient in the Services menu, and probe results"
```

---

### Task 2: `SpeechText.spoken` — markdown to spoken text

**Files:**
- Create: `Sources/AmbientCore/Speech/SpeechText.swift`
- Test: `Tests/AmbientCoreTests/SpeechTextTests.swift`

**Interfaces:**
- Produces: `public enum SpeechText` with `public static func spoken(_ markdown: String, readCode: Bool = false) -> String`. Lines are joined with `"\n"`; the result is `""` when nothing is worth reading.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter SpeechTextTests`
Expected: FAIL, `cannot find 'SpeechText' in scope`.

- [ ] **Step 3: Implement**

```swift
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
                if let code = fence { closeFence(code); fence = nil } else { fence = [] }
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
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SpeechTextTests`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/Speech/SpeechText.swift Tests/AmbientCoreTests/SpeechTextTests.swift
git commit -m "feat(speech): turn agent markdown into text that reads well aloud"
```

---

### Task 3: `SpeechText.chunks` — short chunks for fast starts

**Files:**
- Modify: `Sources/AmbientCore/Speech/SpeechText.swift`
- Test: `Tests/AmbientCoreTests/SpeechChunkTests.swift`

**Interfaces:**
- Produces: `public static func chunks(_ text: String, max limit: Int = 300) -> [String]`. Every chunk is non-empty and at most `limit` characters (grapheme clusters).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AmbientCore

@Suite struct SpeechChunkTests {
    @Test func sentencesPackUpToTheLimit() {
        #expect(SpeechText.chunks("First one. Second one! Third?", max: 20) == ["First one.", "Second one! Third?"])
        #expect(SpeechText.chunks("First one. Second one! Third?") == ["First one. Second one! Third?"])
    }

    @Test func decimalsDontEndSentences() {
        #expect(SpeechText.chunks("Version 1.5 is out. Next.", max: 20) == ["Version 1.5 is out.", "Next."])
    }

    @Test func newlinesSeparateSentences() {
        #expect(SpeechText.chunks("Summary.\nFixed it") == ["Summary. Fixed it"])
    }

    @Test func longSentencesSplitAtClauses() {
        let s = "alpha beta gamma delta, epsilon zeta eta theta, iota kappa"
        #expect(SpeechText.chunks(s, max: 30) == ["alpha beta gamma delta,", "epsilon zeta eta theta,", "iota kappa"])
    }

    @Test func longClausesSplitAtWords() {
        let s = Array(repeating: "word", count: 30).joined(separator: " ")
        let chunks = SpeechText.chunks(s, max: 50)
        #expect(chunks.allSatisfy { $0.count <= 50 && !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        #expect(chunks.joined(separator: " ") == s)
    }

    @Test func emptyTextHasNoChunks() {
        #expect(SpeechText.chunks("") == [])
        #expect(SpeechText.chunks("  \n ") == [])
    }

    @Test func cjkWithoutPunctuation() {
        let s = String(repeating: "漢字", count: 500)
        let chunks = SpeechText.chunks(s)
        #expect(chunks.map(\.count) == [300, 300, 300, 100])
        #expect(chunks.joined() == s)
    }

    @Test func emojiAreNeverSplit() {
        let s = String(repeating: "👩‍💻", count: 400)
        let chunks = SpeechText.chunks(s)
        #expect(chunks.allSatisfy { $0.count <= 300 && $0.allSatisfy { $0 == "👩‍💻" } })
        #expect(chunks.joined() == s)
    }

    @Test func hugeSelectionIsFast() {
        let s = String(repeating: "word ", count: 40_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = SpeechText.chunks(s) }
        #expect(elapsed < .seconds(2))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter SpeechChunkTests`
Expected: FAIL, `type 'SpeechText' has no member 'chunks'`.

- [ ] **Step 3: Implement** (append inside `enum SpeechText`)

```swift
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
            if c.isNewline { push(); continue }
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
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SpeechChunkTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/Speech/SpeechText.swift Tests/AmbientCoreTests/SpeechChunkTests.swift
git commit -m "feat(speech): split spoken text into short chunks without breaking characters"
```

---

### Task 4: `SpeechPipeline` — prepare the next chunk while one plays

**Files:**
- Create: `Sources/AmbientCore/Speech/SpeechPipeline.swift`
- Test: `Tests/AmbientCoreTests/SpeechPipelineTests.swift`

**Interfaces:**
- Produces: `public enum SpeechPipeline { public static func run<Audio: Sendable>(_ chunks: [String], synthesize: @escaping @Sendable (String) async throws -> Audio, play: (Audio) async -> Void) async throws }`. It rethrows the first synthesis error, throws `CancellationError` when cancelled, and never calls `play` after either.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AmbientCore

private actor Events {
    var items: [String] = []
    func add(_ s: String) { items.append(s) }
    func has(_ s: String) -> Bool { items.contains(s) }
}

private final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Error>?
}

private struct Boom: Error {}

@Suite struct SpeechPipelineTests {
    @Test func playsInOrder() async throws {
        let events = Events()
        try await SpeechPipeline.run(["a", "b", "c"], synthesize: { $0 }, play: { await events.add("play:\($0)") })
        #expect(await events.items == ["play:a", "play:b", "play:c"])
    }

    @Test func preparesTheNextChunkWhileOnePlays() async throws {
        let events = Events()
        try await SpeechPipeline.run(["a", "b"], synthesize: { text in
            await events.add("synth:\(text)")
            return text
        }, play: { audio in
            if audio == "a" {
                for _ in 0..<200 where !(await events.has("synth:b")) { try? await Task.sleep(nanoseconds: 5_000_000) }
            }
            await events.add("play:\(audio)")
        })
        #expect(await events.items == ["synth:a", "synth:b", "play:a", "play:b"])
    }

    @Test func stopsAtTheFirstError() async {
        let events = Events()
        await #expect(throws: Boom.self) {
            try await SpeechPipeline.run(["a", "b", "c"], synthesize: { text in
                if text == "b" { throw Boom() }
                return text
            }, play: { await events.add("play:\($0)") })
        }
        #expect(await events.items == ["play:a"])
    }

    @Test func cancelDuringPlayStopsEverything() async {
        let events = Events()
        let box = TaskBox()
        let task = Task {
            try await SpeechPipeline.run(["a", "b", "c"], synthesize: { text in
                await events.add("synth:\(text)")
                return text
            }, play: { audio in
                await events.add("play:\(audio)")
                while box.task == nil { await Task.yield() }
                box.task?.cancel()
            })
        }
        box.task = task
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        let items = await events.items
        #expect(items.filter { $0.hasPrefix("play:") } == ["play:a"])
        #expect(!items.contains("synth:c"))
    }

    @Test func nothingToSay() async throws {
        let events = Events()
        try await SpeechPipeline.run([], synthesize: { $0 }, play: { await events.add("play:\($0)") })
        #expect(await events.items.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter SpeechPipelineTests`
Expected: FAIL, `cannot find 'SpeechPipeline' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Speaks chunks in order, synthesizing chunk n+1 while chunk n plays so there's no gap between them.
public enum SpeechPipeline {
    /// Stops at the first synthesis error, which it rethrows. When the calling task is cancelled it throws
    /// `CancellationError` and plays nothing more, even if a chunk finished synthesizing at that moment.
    public static func run<Audio: Sendable>(_ chunks: [String],
                                            synthesize: @escaping @Sendable (String) async throws -> Audio,
                                            play: (Audio) async -> Void) async throws {
        var pending: Task<Audio, Error>?
        defer { pending?.cancel() }
        func start(_ i: Int) -> Task<Audio, Error>? {
            guard chunks.indices.contains(i) else { return nil }
            let text = chunks[i]
            return Task { try await synthesize(text) }
        }
        pending = start(0)
        var i = 0
        while let current = pending {
            let audio = try await withTaskCancellationHandler {
                try await current.value
            } onCancel: {
                current.cancel()
            }
            try Task.checkCancellation()
            i += 1
            pending = start(i)
            await play(audio)
            try Task.checkCancellation()
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SpeechPipelineTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/Speech/SpeechPipeline.swift Tests/AmbientCoreTests/SpeechPipelineTests.swift
git commit -m "feat(speech): a pipeline that prepares the next chunk while one plays and stops cleanly"
```

---

### Task 5: `VoiceWire` — the helper's protocol

**Files:**
- Create: `Sources/AmbientCore/Speech/VoiceWire.swift`
- Test: `Tests/AmbientCoreTests/VoiceWireTests.swift`

**Interfaces:**
- Produces:
  - `public struct VoiceWire.Request: Codable, Equatable, Sendable { id, text, voice: String; speed: Double }`
  - `public struct VoiceWire.Header: Codable, Equatable, Sendable { id: String; sampleRate: Int?; error: String? }`
  - `public static func line<T: Encodable>(_ value: T) -> Data` (JSON + `\n`)
  - `public static func request(from line: Data) -> Request?`
  - `public static func frame(_ samples: [Float]) -> Data`, `public static let end: Data`
  - `public struct VoiceWire.Reader` with `public mutating func feed(_ data: Data) throws -> [VoiceWire.Event]`
  - `public enum VoiceWire.Event: Equatable, Sendable { case header(Header), samples([Float]), end }`
  - `public enum VoiceWire.WireError: Error, Equatable { case malformedHeader, badFrame(Int) }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AmbientCore

@Suite struct VoiceWireTests {
    private func response(_ id: String, _ frames: [[Float]]) -> Data {
        var d = VoiceWire.line(VoiceWire.Header(id: id, sampleRate: 24_000))
        for f in frames { d.append(VoiceWire.frame(f)) }
        d.append(VoiceWire.end)
        return d
    }

    @Test func requestRoundTrip() throws {
        let r = VoiceWire.Request(id: "1", text: "Hello\nthere", voice: "af_heart", speed: 1.1)
        let line = VoiceWire.line(r)
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(VoiceWire.request(from: line.dropLast()) == r)
        #expect(VoiceWire.request(from: Data("nonsense".utf8)) == nil)
    }

    @Test func readsAWholeResponse() throws {
        var reader = VoiceWire.Reader()
        let events = try reader.feed(response("1", [[0.5, -0.25], [1]]))
        #expect(events == [.header(.init(id: "1", sampleRate: 24_000)), .samples([0.5, -0.25]), .samples([1]), .end])
    }

    @Test func readsByteByByte() throws {
        var reader = VoiceWire.Reader()
        var events: [VoiceWire.Event] = []
        for byte in response("7", [[0.1, 0.2, 0.3]]) { events += try reader.feed(Data([byte])) }
        #expect(events == [.header(.init(id: "7", sampleRate: 24_000)), .samples([0.1, 0.2, 0.3]), .end])
    }

    @Test func readsBackToBackResponses() throws {
        var reader = VoiceWire.Reader()
        let events = try reader.feed(response("1", [[1]]) + response("2", [[2]]))
        #expect(events.count == 6)
        #expect(events[3] == .header(.init(id: "2", sampleRate: 24_000)))
    }

    @Test func errorHeaderEndsTheResponse() throws {
        var reader = VoiceWire.Reader()
        let failed = VoiceWire.line(VoiceWire.Header(id: "1", error: "tooManyTokens"))
        let events = try reader.feed(failed + response("2", [[1]]))
        #expect(events.first == .header(.init(id: "1", error: "tooManyTokens")))
        #expect(events[1] == .header(.init(id: "2", sampleRate: 24_000)))
    }

    @Test func truncatedFrameWaits() throws {
        var reader = VoiceWire.Reader()
        let whole = response("1", [[1, 2, 3, 4]])
        let events = try reader.feed(whole.prefix(whole.count - 9))
        #expect(events == [.header(.init(id: "1", sampleRate: 24_000))])
    }

    @Test func oversizedFrameThrows() {
        var reader = VoiceWire.Reader()
        var data = VoiceWire.line(VoiceWire.Header(id: "1", sampleRate: 24_000))
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: VoiceWire.WireError.badFrame(0x7FFF_FFFF)) { try reader.feed(data) }
    }

    @Test func malformedHeaderThrows() {
        var reader = VoiceWire.Reader()
        #expect(throws: VoiceWire.WireError.malformedHeader) { try reader.feed(Data("dyld: Library not loaded\n".utf8)) }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter VoiceWireTests`
Expected: FAIL, `cannot find 'VoiceWire' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// How Ambient and the `ambient-voice` helper talk over the helper's stdin and stdout.
///
/// Request: one JSON line. Response: a JSON header line, then frames of a little-endian `UInt32` byte count followed
/// by that many bytes of little-endian float32 mono PCM, ending with a zero-length frame. A header with `error` has
/// no frames.
public enum VoiceWire {
    public struct Request: Codable, Equatable, Sendable {
        public var id: String
        public var text: String
        public var voice: String
        public var speed: Double

        public init(id: String, text: String, voice: String, speed: Double) {
            self.id = id
            self.text = text
            self.voice = voice
            self.speed = speed
        }
    }

    public struct Header: Codable, Equatable, Sendable {
        public var id: String
        public var sampleRate: Int?
        public var error: String?

        public init(id: String, sampleRate: Int? = nil, error: String? = nil) {
            self.id = id
            self.sampleRate = sampleRate
            self.error = error
        }
    }

    public enum Event: Equatable, Sendable {
        case header(Header)
        case samples([Float])
        case end
    }

    public enum WireError: Error, Equatable {
        case malformedHeader
        case badFrame(Int)
    }

    /// 16 MB: about three minutes of audio, far more than one chunk produces.
    public static let maxFrameBytes = 16 << 20
    public static let end = Data(count: 4)

    public static func line<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(value)) ?? Data()
        data.append(0x0A)
        return data
    }

    public static func request(from line: Data) -> Request? {
        try? JSONDecoder().decode(Request.self, from: line)
    }

    public static func frame(_ samples: [Float]) -> Data {
        var data = Data()
        withUnsafeBytes(of: UInt32(samples.count * 4).littleEndian) { data.append(contentsOf: $0) }
        for s in samples {
            withUnsafeBytes(of: s.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Reads a stream of responses. Feed it bytes as they arrive; it returns whatever events are complete.
    public struct Reader: Sendable {
        private var buffer = Data()
        private var inFrames = false

        public init() {}

        public mutating func feed(_ data: Data) throws -> [Event] {
            buffer.append(data)
            var events: [Event] = []
            while true {
                if !inFrames {
                    guard let newline = buffer.firstIndex(of: 0x0A) else { break }
                    let line = buffer[buffer.startIndex..<newline]
                    guard let header = try? JSONDecoder().decode(Header.self, from: line) else {
                        throw WireError.malformedHeader
                    }
                    consume(newline - buffer.startIndex + 1)
                    events.append(.header(header))
                    inFrames = header.error == nil
                } else {
                    guard buffer.count >= 4 else { break }
                    let n = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
                    guard n <= VoiceWire.maxFrameBytes, n % 4 == 0 else { throw WireError.badFrame(n) }
                    if n == 0 {
                        consume(4)
                        events.append(.end)
                        inFrames = false
                        continue
                    }
                    guard buffer.count >= 4 + n else { break }
                    let samples = buffer.dropFirst(4).prefix(n).withUnsafeBytes { raw in
                        (0..<n / 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
                    }
                    consume(4 + n)
                    events.append(.samples(samples))
                }
            }
            return events
        }

        /// Drops `count` bytes and rebases, so indices start at zero again.
        private mutating func consume(_ count: Int) {
            buffer = Data(buffer.dropFirst(count))
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter VoiceWireTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/Speech/VoiceWire.swift Tests/AmbientCoreTests/VoiceWireTests.swift
git commit -m "feat(speech): the wire format between Ambient and the offline voice helper"
```

---

### Task 6: `OnlineSpeech` — engine kinds, providers and requests

**Files:**
- Create: `Sources/AmbientCore/Speech/OnlineSpeech.swift`
- Test: `Tests/AmbientCoreTests/OnlineSpeechTests.swift`

**Interfaces:**
- Produces:
  - `public enum SpeechEngineKind: String, CaseIterable, Sendable { case mac, kokoro, online }` with `displayName`
  - `public enum OnlineProvider: String, CaseIterable, Sendable { case openAI, elevenLabs, custom }` with `displayName`, `defaultVoice`, `defaultModel`, `needsKey`
  - `public enum OnlineSpeech` with `sampleRate = 24_000`, `request(provider:baseURL:key:model:voice:text:speed:) -> URLRequest?`, `samples(pcm16:) -> [Float]`, `failure(status:body:provider:) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AmbientCore

@Suite struct OnlineSpeechTests {
    private func body(_ r: URLRequest?) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try #require(r?.httpBody)) as? [String: Any])
    }

    @Test func openAIRequest() throws {
        let r = OnlineSpeech.request(provider: .openAI, baseURL: "", key: "sk-1", model: "gpt-4o-mini-tts",
                                     voice: "alloy", text: "Hi", speed: 9)
        #expect(r?.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(r?.httpMethod == "POST")
        #expect(r?.timeoutInterval == 15)
        #expect(r?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        let b = try body(r)
        #expect(b["input"] as? String == "Hi")
        #expect(b["response_format"] as? String == "pcm")
        #expect(b["speed"] as? Double == 4)
    }

    @Test func customServerWithoutKey() throws {
        let r = OnlineSpeech.request(provider: .custom, baseURL: " http://localhost:8880/v1/ ", key: "", model: "kokoro",
                                     voice: "af_heart", text: "Hi", speed: 1)
        #expect(r?.url?.absoluteString == "http://localhost:8880/v1/audio/speech")
        #expect(r?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(OnlineSpeech.request(provider: .custom, baseURL: "ftp://x", key: "", model: "m", voice: "v", text: "t", speed: 1) == nil)
        #expect(OnlineSpeech.request(provider: .custom, baseURL: "", key: "", model: "m", voice: "v", text: "t", speed: 1) == nil)
    }

    @Test func elevenLabsRequest() throws {
        let r = OnlineSpeech.request(provider: .elevenLabs, baseURL: "", key: "xi", model: "eleven_flash_v2_5",
                                     voice: "21m00Tcm4TlvDq8ikWAM", text: "Hi", speed: 2)
        #expect(r?.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM?output_format=pcm_24000")
        #expect(r?.value(forHTTPHeaderField: "xi-api-key") == "xi")
        let b = try body(r)
        #expect(b["text"] as? String == "Hi")
        #expect((b["voice_settings"] as? [String: Any])?["speed"] as? Double == 1.2)
        #expect(OnlineSpeech.request(provider: .elevenLabs, baseURL: "", key: "xi", model: "m", voice: "../x", text: "t", speed: 1) == nil)
    }

    @Test func pcm16ToFloat() {
        let data = Data([0x00, 0x00, 0x00, 0x40, 0x00, 0x80])  // 0, 16384, -32768
        #expect(OnlineSpeech.samples(pcm16: data) == [0, 0.5, -1])
        #expect(OnlineSpeech.samples(pcm16: Data([0x01])) == [])
    }

    @Test func failureMessages() {
        #expect(OnlineSpeech.failure(status: 401, body: Data(), provider: .openAI) == "OpenAI didn't accept the API key.")
        #expect(OnlineSpeech.failure(status: 429, body: Data(), provider: .elevenLabs)
                == "ElevenLabs is limiting requests. Try again in a minute.")
        let body = Data(#"{"error":{"message":"Input too long"}}"#.utf8)
        #expect(OnlineSpeech.failure(status: 400, body: body, provider: .openAI)
                == "OpenAI couldn't read it aloud (error 400). Input too long")
        #expect(OnlineSpeech.failure(status: 500, body: Data("<html>".utf8), provider: .custom)
                == "Your server couldn't read it aloud (error 500).")
    }

    @Test func providerDefaults() {
        #expect(OnlineProvider.openAI.needsKey && OnlineProvider.elevenLabs.needsKey && !OnlineProvider.custom.needsKey)
        #expect(SpeechEngineKind.allCases.map(\.displayName) == ["Mac voice", "Offline model", "Online model"])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter OnlineSpeechTests`
Expected: FAIL, `cannot find 'OnlineSpeech' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The three ways Ambient can read aloud.
public enum SpeechEngineKind: String, CaseIterable, Sendable {
    case mac, kokoro, online

    public var displayName: String {
        switch self {
        case .mac: "Mac voice"
        case .kokoro: "Offline model"
        case .online: "Online model"
        }
    }
}

public enum OnlineProvider: String, CaseIterable, Sendable {
    case openAI, elevenLabs, custom

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        case .custom: "Your server"
        }
    }

    public var defaultVoice: String {
        switch self {
        case .openAI: "alloy"
        case .elevenLabs: "21m00Tcm4TlvDq8ikWAM"
        case .custom: "af_heart"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini-tts"
        case .elevenLabs: "eleven_flash_v2_5"
        case .custom: "kokoro"
        }
    }

    /// A local OpenAI-compatible server usually takes no key.
    public var needsKey: Bool { self != .custom }
}

/// Requests to online text-to-speech services. Every provider answers with 24 kHz 16-bit mono PCM.
public enum OnlineSpeech {
    public static let sampleRate = 24_000

    /// Nil when the settings can't make a valid request (a bad server URL or voice id).
    public static func request(provider: OnlineProvider, baseURL: String, key: String, model: String,
                               voice: String, text: String, speed: Double) -> URLRequest? {
        var request: URLRequest
        let body: [String: Any]
        switch provider {
        case .openAI, .custom:
            let base = provider == .openAI ? "https://api.openai.com/v1" : baseURL.trimmingCharacters(in: .whitespaces)
            guard !base.isEmpty,
                  let url = URL(string: base.hasSuffix("/") ? base + "audio/speech" : base + "/audio/speech"),
                  let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
            request = URLRequest(url: url)
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = ["model": model, "input": text, "voice": voice, "response_format": "pcm",
                    "speed": min(4, max(0.25, speed))]
        case .elevenLabs:
            guard voice.range(of: "^[A-Za-z0-9]{1,64}$", options: .regularExpression) != nil,
                  let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=pcm_24000")
            else { return nil }
            request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            body = ["text": text, "model_id": model, "voice_settings": ["speed": min(1.2, max(0.7, speed))]]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// 16-bit little-endian PCM as floats in -1...1. A trailing odd byte is ignored.
    public static func samples(pcm16 data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            (0..<raw.count / 2).map { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self))) / 32_768 }
        }
    }

    /// What to tell the user when a provider answers with an error.
    public static func failure(status: Int, body: Data, provider: OnlineProvider) -> String {
        let name = provider.displayName
        switch status {
        case 401, 403: return "\(name) didn't accept the API key."
        case 429: return "\(name) is limiting requests. Try again in a minute."
        default:
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let detail = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? ((json?["detail"] as? [String: Any])?["message"] as? String)
                ?? (json?["detail"] as? String)
            let base = "\(name) couldn't read it aloud (error \(status))."
            return detail.map { base + " " + Trim.truncate($0, max: 120) } ?? base
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter OnlineSpeechTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/Speech/OnlineSpeech.swift Tests/AmbientCoreTests/OnlineSpeechTests.swift
git commit -m "feat(speech): engine kinds, online providers and their requests"
```

---

### Task 7: `VoicePackManifest` — what the offline voice downloads, pinned

**Files:**
- Create: `Sources/AmbientCore/Speech/VoicePack.swift`
- Create: `Sources/AmbientCore/Speech/VoicePackPin.swift`
- Modify: `Sources/AmbientCore/Paths.swift` (add `voice`)
- Modify: `Sources/ambient/Commands.swift` (hidden `voice-files` command)
- Test: `Tests/AmbientCoreTests/VoicePackTests.swift`

**Interfaces:**
- Produces:
  - `public struct VoicePackFile: Equatable, Sendable { path: String; url: URL; sha256: String; bytes: Int64 }`
  - `public struct KokoroVoiceOption: Equatable, Sendable, Identifiable { id, name, accent: String }`
  - `public struct VoicePackManifest` with `version`, `helper`, `files`, `voices`, `minimumMacOS`, `teamID`, `isPublished`, `totalBytes`, `folderName`, `defaultVoice`, `support(osMajor:isAppleSilicon:) -> Support`, `static let current`
  - `public enum VoicePackManifest.Support: Equatable, Sendable { case supported, needsNewerMacOS(Int), needsAppleSilicon }`
  - `public enum VoicePackPin { version: String; helperSHA256: String; helperBytes: Int64 }`
  - `public enum FileHash { static func sha256(of: URL) throws -> String }`
  - `AmbientPaths.voice: URL` (`~/.ambient/voice`)

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AmbientCore

@Suite struct VoicePackTests {
    let pack = VoicePackManifest.current

    @Test func everyDownloadIsHTTPSAndPinned() {
        for f in pack.files {
            #expect(f.url.scheme == "https")
            #expect(f.url.absoluteString.contains("/resolve/e02c9eada7ce7416798af36b190a8a2dd2ecd566/"))
            #expect(f.sha256.count == 64)
            #expect(f.bytes > 0)
        }
        #expect(pack.helper.url.absoluteString
                == "https://github.com/viveky259259/ambient/releases/download/voice-\(VoicePackPin.version)/ambient-voice-\(VoicePackPin.version).zip")
    }

    @Test func pathsStayInsideThePack() {
        let paths = ([pack.helper] + pack.files).map(\.path)
        #expect(Set(paths).count == paths.count)
        #expect(paths.allSatisfy { !$0.hasPrefix("/") && !$0.contains("..") })
    }

    @Test func everyVoiceHasItsFile() {
        #expect(pack.voices.first?.id == pack.defaultVoice)
        for v in pack.voices { #expect(pack.files.contains { $0.path == "voices/\(v.id).safetensors" }) }
    }

    @Test func publishedOnlyWithAPinnedHelper() {
        #expect(pack.isPublished == (pack.helper.sha256.count == 64))
        #expect(pack.totalBytes == pack.files.reduce(pack.helper.bytes) { $0 + $1.bytes })
        #expect(pack.folderName == "kokoro-\(VoicePackPin.version)")
    }

    @Test func support() {
        #expect(pack.support(osMajor: 15, isAppleSilicon: true) == .supported)
        #expect(pack.support(osMajor: 14, isAppleSilicon: true) == .needsNewerMacOS(15))
        #expect(pack.support(osMajor: 26, isAppleSilicon: false) == .needsAppleSilicon)
    }

    @Test func hashesAFile() throws {
        let url = try shortTempDir().appendingPathComponent("abc")
        try Data("abc".utf8).write(to: url)
        #expect(try FileHash.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func voiceFolderLivesInAmbientHome() {
        let paths = AmbientPaths(userHome: URL(fileURLWithPath: "/Users/x"))
        #expect(paths.voice.path == "/Users/x/.ambient/voice")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter VoicePackTests`
Expected: FAIL, `cannot find 'VoicePackManifest' in scope`.

- [ ] **Step 3: Implement `VoicePackPin.swift`**

```swift
/// The published offline voice helper. `scripts/pin-voice-helper.sh` rewrites this file after uploading a helper to
/// the `voice-<version>` release; until then the offline voice reports that it isn't available in this build.
public enum VoicePackPin {
    public static let version = "1"
    public static let helperSHA256 = ""
    public static let helperBytes: Int64 = 0
}
```

- [ ] **Step 4: Implement `VoicePack.swift`**

```swift
import CryptoKit
import Foundation

public struct VoicePackFile: Equatable, Sendable {
    /// Where the file goes inside the pack folder.
    public let path: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
}

public struct KokoroVoiceOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let accent: String
}

/// Everything the offline voice downloads, each file pinned by hash. Compiled into the app, so a download can't be
/// swapped for something else.
public struct VoicePackManifest: Equatable, Sendable {
    public enum Support: Equatable, Sendable {
        case supported
        case needsNewerMacOS(Int)
        case needsAppleSilicon
    }

    public let version: String
    /// A zip holding the `ambient-voice` folder.
    public let helper: VoicePackFile
    public let files: [VoicePackFile]
    public let voices: [KokoroVoiceOption]
    public let minimumMacOS: Int
    /// The Developer ID team the helper must be signed by.
    public let teamID: String

    public var isPublished: Bool { helper.sha256.count == 64 }
    public var totalBytes: Int64 { files.reduce(helper.bytes) { $0 + $1.bytes } }
    public var folderName: String { "kokoro-\(version)" }
    public var defaultVoice: String { voices[0].id }

    public func support(osMajor: Int, isAppleSilicon: Bool) -> Support {
        if !isAppleSilicon { return .needsAppleSilicon }
        if osMajor < minimumMacOS { return .needsNewerMacOS(minimumMacOS) }
        return .supported
    }

    /// Kokoro-82M (Apache-2.0) in the MLX layout kokoro-ios loads, from Hugging Face at a fixed commit.
    public static let current: VoicePackManifest = {
        let commit = "e02c9eada7ce7416798af36b190a8a2dd2ecd566"
        func hf(_ path: String, _ sha256: String, _ bytes: Int64) -> VoicePackFile {
            VoicePackFile(path: path,
                          url: URL(string: "https://huggingface.co/prince-canuma/Kokoro-82M/resolve/\(commit)/\(path)")!,
                          sha256: sha256, bytes: bytes)
        }
        let voices: [(id: String, name: String, accent: String, sha256: String)] = [
            ("af_heart", "Heart", "American", "4e40b08984cd84a86b4d07960939bd85bb6b3747dd747b7de48dca3aaeab37ca"),
            ("af_bella", "Bella", "American", "a18024b9332f5ff217c7f604cbe94449a3ca51c3b8d85500e31cd3cbdc4ef6ce"),
            ("af_nicole", "Nicole", "American", "769ee38efeb131196eaab5ed43592b315bba829881d4aee7411872efa6cf05c6"),
            ("am_michael", "Michael", "American", "19a8661430456e2bbf0a68b52fa9b49678bb0fb7418619f868df77921f5aa43c"),
            ("bf_emma", "Emma", "British", "ed92055e1ed96f2a0b4a52b76956dcfd76627bd548c33801743a62c0817dec01"),
            ("bm_george", "George", "British", "a3a6682cde622e7aee35597b91947fa018f78be101a97587a100effe227e5a21"),
        ]
        let version = VoicePackPin.version
        return VoicePackManifest(
            version: version,
            helper: VoicePackFile(
                path: "ambient-voice.zip",
                url: URL(string: "https://github.com/viveky259259/ambient/releases/download/voice-\(version)/ambient-voice-\(version).zip")!,
                sha256: VoicePackPin.helperSHA256, bytes: VoicePackPin.helperBytes),
            files: [hf("kokoro-v1_0.safetensors", "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8", 327_115_152)]
                + voices.map { hf("voices/\($0.id).safetensors", $0.sha256, 522_339) },
            voices: voices.map { KokoroVoiceOption(id: $0.id, name: $0.name, accent: $0.accent) },
            minimumMacOS: 15,
            teamID: "CU3457GT8T")
    }()
}

public enum FileHash {
    /// Lowercase hex SHA-256, read a megabyte at a time.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 5: Add the voice folder to `AmbientPaths`**

In `Sources/AmbientCore/Paths.swift`, after `public var logs`:

```swift
    /// Downloaded offline voice packs, one folder per version.
    public var voice: URL { home.appendingPathComponent("voice", isDirectory: true) }
```

- [ ] **Step 6: Add the hidden `voice-files` command**

In `Sources/ambient/Commands.swift`, add a case beside `"version"`:

```swift
        // Undocumented, for scripts/fetch-voice-pack.sh: the offline voice's model files, one "path url sha256" per line.
        case "voice-files":
            for f in VoicePackManifest.current.files { print("\(f.path) \(f.url.absoluteString) \(f.sha256)") }
            return 0
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter VoicePackTests`
Expected: PASS (7 tests).

Run: `swift run ambient voice-files | head -2`
Expected: `kokoro-v1_0.safetensors https://huggingface.co/prince-canuma/Kokoro-82M/resolve/e02c9ead…/kokoro-v1_0.safetensors 4e9ecdf…` then `voices/af_heart.safetensors …`.

- [ ] **Step 8: Commit**

```bash
git add Sources/AmbientCore/Speech/VoicePack.swift Sources/AmbientCore/Speech/VoicePackPin.swift Sources/AmbientCore/Paths.swift Sources/ambient/Commands.swift Tests/AmbientCoreTests/VoicePackTests.swift
git commit -m "feat(speech): the offline voice pack manifest, pinned by hash"
```

---

### Task 8: Mac voice end to end — engine, player, controller, preferences

After this task, selecting text and pressing the Services shortcut reads it with the Mac voice.

**Files:**
- Modify: `Sources/AmbientApp/Preferences.swift`
- Create: `Sources/AmbientApp/Speech/SpeechEngine.swift`
- Create: `Sources/AmbientApp/Speech/MacVoice.swift`
- Create: `Sources/AmbientApp/Speech/SpeechPlayer.swift`
- Create: `Sources/AmbientApp/Speech/SpeechController.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `SpeechText.spoken`, `SpeechText.chunks`, `SpeechPipeline.run`, `SpeechEngineKind`.
- Produces:
  - `Preferences`: `speechEngine: String?`, `macVoice`, `kokoroVoice`, `onlineProvider`, `onlineVoice`, `onlineModel`, `onlineBaseURL: String`, `speechRate: Double`, `speechReadsCode: Bool`, `speechAccessExplained: Bool`, computed `speechEngineKind: SpeechEngineKind?`
  - `struct PCM: @unchecked Sendable { let buffer: AVAudioPCMBuffer; static func mono(_ samples: [Float], sampleRate: Int) throws -> PCM }`
  - `struct SpeechFailure: LocalizedError { let message: String; var offerMacVoice = false }`
  - `protocol SpeechEngine: AnyObject { func audio(for text: String) async throws -> PCM }`
  - `enum SpeechState: Equatable { case idle, preparing, speaking, failed(String, offerMacVoice: Bool) }`
  - `final class SpeechController: ObservableObject` (main thread) with `state`, `level`, `isActive`, `toggle(_ text: String?)`, `stop()`, `useMacVoice()`, `preview(_ kind: SpeechEngineKind)`, `fail(_ message: String)`, and settable `makeEngine: (SpeechEngineKind) throws -> SpeechEngine` and `chooseEngine: (@escaping (Bool) -> Void) -> Void`

- [ ] **Step 1: Add the speech preferences**

In `Preferences`, add after `petOrigin`:

```swift
    /// A `SpeechEngineKind` raw value; nil until the voice chooser has run.
    @Published var speechEngine: String? { didSet { defaults.set(speechEngine, forKey: "speechEngine") } }
    /// An `AVSpeechSynthesisVoice` identifier; empty for the system's default voice.
    @Published var macVoice: String { didSet { defaults.set(macVoice, forKey: "macVoice") } }
    @Published var kokoroVoice: String { didSet { defaults.set(kokoroVoice, forKey: "kokoroVoice") } }
    /// An `OnlineProvider` raw value.
    @Published var onlineProvider: String { didSet { defaults.set(onlineProvider, forKey: "onlineProvider") } }
    @Published var onlineVoice: String { didSet { defaults.set(onlineVoice, forKey: "onlineVoice") } }
    @Published var onlineModel: String { didSet { defaults.set(onlineModel, forKey: "onlineModel") } }
    /// For `OnlineProvider.custom`: an OpenAI-compatible base URL such as http://localhost:8880/v1.
    @Published var onlineBaseURL: String { didSet { defaults.set(onlineBaseURL, forKey: "onlineBaseURL") } }
    /// 1 is normal speed; 0.5 to 2.
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: "speechRate") } }
    @Published var speechReadsCode: Bool { didSet { defaults.set(speechReadsCode, forKey: "speechReadsCode") } }
    /// The Accessibility explanation has been shown once (hotkey route only).
    @Published var speechAccessExplained: Bool { didSet { defaults.set(speechAccessExplained, forKey: "speechAccessExplained") } }
```

Add to `defaults.register(defaults:)`:

```swift
            "macVoice": "",
            "kokoroVoice": VoicePackManifest.current.defaultVoice,
            "onlineProvider": OnlineProvider.openAI.rawValue,
            "onlineVoice": OnlineProvider.openAI.defaultVoice,
            "onlineModel": OnlineProvider.openAI.defaultModel,
            "onlineBaseURL": "http://localhost:8880/v1",
            "speechRate": 1.0,
            "speechReadsCode": false,
            "speechAccessExplained": false,
```

Add to `init` after `petOrigin` is set:

```swift
        speechEngine = defaults.string(forKey: "speechEngine")
        macVoice = defaults.string(forKey: "macVoice") ?? ""
        kokoroVoice = defaults.string(forKey: "kokoroVoice") ?? VoicePackManifest.current.defaultVoice
        onlineProvider = defaults.string(forKey: "onlineProvider") ?? OnlineProvider.openAI.rawValue
        onlineVoice = defaults.string(forKey: "onlineVoice") ?? OnlineProvider.openAI.defaultVoice
        onlineModel = defaults.string(forKey: "onlineModel") ?? OnlineProvider.openAI.defaultModel
        onlineBaseURL = defaults.string(forKey: "onlineBaseURL") ?? "http://localhost:8880/v1"
        speechRate = defaults.double(forKey: "speechRate")
        speechReadsCode = defaults.bool(forKey: "speechReadsCode")
        speechAccessExplained = defaults.bool(forKey: "speechAccessExplained")
```

Add beside `var pet`:

```swift
    var speechEngineKind: SpeechEngineKind? { speechEngine.flatMap(SpeechEngineKind.init(rawValue:)) }
    var provider: OnlineProvider { OnlineProvider(rawValue: onlineProvider) ?? .openAI }
```

- [ ] **Step 2: Write `SpeechEngine.swift`**

```swift
import AVFoundation

/// Audio for one chunk. AVAudioPCMBuffer isn't Sendable; a buffer is handed from engine to player once and never
/// shared.
struct PCM: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    static func mono(_ samples: [Float], sampleRate: Int) throws -> PCM {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let channel = buffer.floatChannelData?[0] else {
            throw SpeechFailure(message: "Couldn't prepare the audio.")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return PCM(buffer: buffer)
    }
}

/// A failure the user should read. `offerMacVoice` adds a "Use Mac voice" button.
struct SpeechFailure: LocalizedError {
    let message: String
    var offerMacVoice = false
    var errorDescription: String? { message }
}

/// Turns one chunk of text into audio. Calls for one engine never overlap: the pipeline asks for the next chunk only
/// after the previous one is ready.
protocol SpeechEngine: AnyObject {
    func audio(for text: String) async throws -> PCM
}
```

- [ ] **Step 3: Write `MacVoice.swift`**

```swift
import AVFoundation

/// The voices that come with macOS, including downloaded Premium voices and Personal Voice. Offline.
final class MacVoice: SpeechEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceID: String
    private let rate: Double

    init(voiceID: String, rate: Double) {
        self.voiceID = voiceID
        self.rate = rate
    }

    func audio(for text: String) async throws -> PCM {
        let utterance = AVSpeechUtterance(string: text)
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) { utterance.voice = voice }
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        let once = ResumeOnce<PCM>()
        let synthesizer = self.synthesizer
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                var parts: [AVAudioPCMBuffer] = []
                synthesizer.write(utterance) { buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength > 0, let copy = Self.copy(pcm) {
                        parts.append(copy)
                        return
                    }
                    // A zero-length buffer marks the end.
                    if let joined = Self.join(parts) {
                        once.resume(returning: PCM(buffer: joined))
                    } else {
                        once.resume(throwing: SpeechFailure(message: "The Mac voice produced no audio."))
                    }
                }
            }
        } onCancel: {
            synthesizer.stopSpeaking(at: .immediate)
            once.resume(throwing: CancellationError())
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        join([buffer])
    }

    /// One buffer holding all of `parts`, in the first part's format. Works for any PCM layout.
    private static func join(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let format = parts.first?.format else { return nil }
        let frames = parts.reduce(0) { $0 + $1.frameLength }
        guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let destination = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
        var offset = 0
        for part in parts where part.format == format {
            let source = UnsafeMutableAudioBufferListPointer(part.mutableAudioBufferList)
            let bytes = Int(part.frameLength) * bytesPerFrame
            for (i, buffer) in source.enumerated() where i < destination.count {
                guard let from = buffer.mData, let to = destination[i].mData else { continue }
                (to + offset).copyMemory(from: from, byteCount: bytes)
            }
            offset += bytes
        }
        out.frameLength = AVAudioFrameCount(offset / bytesPerFrame)
        for i in 0..<destination.count { destination[i].mDataByteSize = UInt32(offset) }
        return out
    }
}

/// Resumes a continuation exactly once, whichever of the callback or a cancellation gets there first, and even if
/// one arrives before the continuation is set.
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var early: Result<T, Error>?
    private var done = false

    func set(_ c: CheckedContinuation<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        if let early {
            done = true
            c.resume(with: early)
        } else {
            continuation = c
        }
    }

    func resume(returning value: T) { finish(.success(value)) }
    func resume(throwing error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !done, early == nil else { return }
        if let c = continuation {
            continuation = nil
            done = true
            c.resume(with: result)
        } else {
            early = result
        }
    }
}
```

- [ ] **Step 4: Write `SpeechPlayer.swift`**

```swift
import AVFoundation

/// One audio engine for every voice: converts each chunk to 24 kHz mono and plays chunks back to back. Used from the
/// main thread, like the rest of the app. A job token guards against a stopped job's audio sneaking in after a new
/// one starts: scheduling happens on the main thread, where `stop()` runs, so it sees the token `stop()` cleared.
final class SpeechPlayer {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var job = 0
    private var lastLevelAt = Date.distantPast
    /// Loudness 0...1, about 15 times a second while playing, on the main thread.
    var onLevel: (Float) -> Void = { _ in }

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Self.format)
    }

    func begin(_ job: Int) {
        stop()
        self.job = job
    }

    /// Returns when the chunk has played, or right away if it belongs to a stopped job. Callable from any thread.
    func play(_ pcm: PCM, job: Int) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                guard job == self.job, let buffer = self.convert(pcm.buffer), self.startEngine() else {
                    c.resume()
                    return
                }
                if !self.node.isPlaying { self.node.play() }
                // Called when the buffer has played, and also when the player is stopped.
                self.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in c.resume() }
            }
        }
    }

    /// Stops sound now. A waiting `play` returns.
    func stop() {
        job = 0
        node.stop()
        if engine.isRunning {
            engine.mainMixerNode.removeTap(onBus: 0)
            engine.stop()
        }
        onLevel(0)
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            let level = Self.level(buffer)
            DispatchQueue.main.async { self?.publish(level) }
        }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func publish(_ level: Float) {
        let now = Date()
        guard job != 0, now.timeIntervalSince(lastLevelAt) > 1.0 / 15 else { return }
        lastLevelAt = now
        onLevel(level)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == Self.format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: Self.format) else { return nil }
        let ratio = Self.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    private static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot() * 4)
    }
}
```

- [ ] **Step 5: Write `SpeechController.swift`**

```swift
import AmbientCore
import AppKit
import Combine

enum SpeechState: Equatable {
    case idle
    case preparing
    case speaking
    case failed(String, offerMacVoice: Bool)
}

/// Reads selected text aloud: one job at a time, the shortcut toggles it, and failures are shown rather than
/// papered over with another engine. Used from the main thread; the job hops back to it to publish.
final class SpeechController: ObservableObject {
    @Published private(set) var state: SpeechState = .idle
    @Published private(set) var level: Float = 0

    /// Builds the engine for a kind. Set by the app delegate, which owns the pack folder and the Keychain.
    var makeEngine: (SpeechEngineKind) throws -> SpeechEngine = { _ in throw SpeechFailure(message: "No voice is set up.") }
    /// Shows the voice chooser the first time; calls back with true once a voice is chosen.
    var chooseEngine: (@escaping (Bool) -> Void) -> Void = { $0(false) }

    private let prefs: Preferences
    private let player = SpeechPlayer()
    private var job: Task<Void, Never>?
    private var jobID = 0
    private var lastText: String?
    private var clearFailure: DispatchWorkItem?

    static let sample = "Hi. This is the voice Ambient will use to read your agents' replies."

    init(prefs: Preferences) {
        self.prefs = prefs
        player.onLevel = { [weak self] in self?.level = $0 }
    }

    var isActive: Bool { state == .preparing || state == .speaking }

    /// The shortcut or the Services item. Reads `text`; stops instead when it's empty or already being read.
    func toggle(_ text: String?) {
        let spoken = SpeechText.spoken(text ?? "", readCode: prefs.speechReadsCode)
        if isActive, spoken.isEmpty || spoken == lastText {
            stop()
            return
        }
        guard !spoken.isEmpty else {
            NSSound(named: "Tink")?.play()
            fail("Select some text first")
            return
        }
        guard let kind = prefs.speechEngineKind else {
            chooseEngine { [weak self] chosen in if chosen { self?.toggle(text) } }
            return
        }
        start(spoken, kind: kind)
    }

    /// Reads a sample with `kind` without saving it as the choice.
    func preview(_ kind: SpeechEngineKind) {
        start(Self.sample, kind: kind)
    }

    func stop() {
        cancelJob()
        state = .idle
    }

    func useMacVoice() {
        prefs.speechEngine = SpeechEngineKind.mac.rawValue
        stop()
    }

    func fail(_ message: String, offerMacVoice: Bool = false) {
        state = .failed(message, offerMacVoice: offerMacVoice)
        clearFailure?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .failed = self.state else { return }
            self.state = .idle
        }
        clearFailure = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (offerMacVoice ? 10 : 5), execute: work)
    }

    private func start(_ text: String, kind: SpeechEngineKind) {
        cancelJob()
        let engine: SpeechEngine
        do {
            engine = try makeEngine(kind)
        } catch {
            report(error)
            return
        }
        jobID += 1
        let id = jobID
        lastText = text
        state = .preparing
        player.begin(id)
        let chunks = SpeechText.chunks(text)
        let player = self.player
        job = Task { [weak self] in
            do {
                try await SpeechPipeline.run(chunks, synthesize: { try await engine.audio(for: $0) }, play: { pcm in
                    await MainActor.run {
                        if self?.jobID == id, self?.state == .preparing { self?.state = .speaking }
                    }
                    await player.play(pcm, job: id)
                })
                await MainActor.run { self?.finish(id, error: nil) }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self?.finish(id, error: error) }
            }
        }
    }

    private func finish(_ id: Int, error: Error?) {
        guard id == jobID else { return }
        job = nil
        lastText = nil
        player.stop()
        if let error { report(error) } else { state = .idle }
    }

    private func report(_ error: Error) {
        if let failure = error as? SpeechFailure {
            fail(failure.message, offerMacVoice: failure.offerMacVoice)
        } else {
            fail(error.localizedDescription)
        }
    }

    private func cancelJob() {
        job?.cancel()
        job = nil
        lastText = nil
        player.stop()
    }
}
```

- [ ] **Step 6: Wire it into `AppDelegate`**

Add properties:

```swift
    private lazy var speech = SpeechController(prefs: prefs)
```

Replace the probe handler from Task 1 with:

```swift
        speech.makeEngine = { [weak self] kind in
            guard let self else { throw SpeechFailure(message: "Ambient is quitting.") }
            return try self.engine(for: kind)
        }
        // Until the voice chooser exists (Task 14), the first use picks the Mac voice.
        speech.chooseEngine = { [weak self] done in
            self?.prefs.speechEngine = SpeechEngineKind.mac.rawValue
            done(true)
        }
        let selectionService = SelectionService { [weak self] text in self?.speech.toggle(text) }
        selectionService.register()
        self.selectionService = selectionService
```

And add the factory method to `AppDelegate`:

```swift
    // MARK: - Speech

    private func engine(for kind: SpeechEngineKind) throws -> SpeechEngine {
        switch kind {
        case .mac:
            return MacVoice(voiceID: prefs.macVoice, rate: prefs.speechRate)
        case .online, .kokoro:
            throw SpeechFailure(message: "\(kind.displayName) isn't set up yet.", offerMacVoice: true)
        }
    }
```

- [ ] **Step 7: Build, run and check by hand**

Run: `swift build && scripts/build-app.sh --run`
Expected: build succeeds; Ambient relaunches.

Check, in Terminal: select a paragraph of an agent reply that contains a fenced code block, and press the Services shortcut. You hear it read with the system voice, the code block read as "Code block, N lines", and no markdown symbols. Press the shortcut again with the same selection: it stops at once. Select something else and press it mid-speech: the first stops and the new one starts, with no overlap. Select only spaces and press it: you hear Tink.

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/AmbientApp/Preferences.swift Sources/AmbientApp/Speech Sources/AmbientApp/AppDelegate.swift
git commit -m "feat(speech): read the selection aloud with the Mac voice"
```

---

### Task 9: Hotkey route — ⌃⌥⌘S with Accessibility (only if the probe chose it)

Skip this task if the spec's probe decision is "Services route".

**Files:**
- Create: `Sources/AmbientApp/Speech/HotKey.swift`
- Create: `Sources/AmbientApp/Speech/SelectionReader.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`
- Modify: `Resources/Info.plist` (remove `NSKeyEquivalent` from the service, so the Services item has no shortcut competing with the hotkey)

**Interfaces:**
- Consumes: `SpeechController.toggle`, `SpeechController.fail`, `Preferences.speechAccessExplained`.
- Produces: `final class HotKey { init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) }`; `enum SelectionReader { static var isTrusted: Bool; static func askForAccess(); @MainActor static func selectedText() async -> String? }`

- [ ] **Step 1: Write `HotKey.swift`**

```swift
import Carbon

/// A system-wide shortcut through Carbon's hotkey API, which needs no permission to register.
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x414D_4253), id: 1)  // "AMBS"
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// ⌃⌥⌘S.
    static func speakSelection(_ action: @escaping () -> Void) -> HotKey? {
        HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), action: action)
    }
}
```

- [ ] **Step 2: Write `SelectionReader.swift`**

```swift
import AppKit
import ApplicationServices
import Carbon

/// The selected text in the frontmost app, through Accessibility, falling back to copying it.
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @MainActor static func selectedText() async -> String? {
        if let text = accessibilitySelection(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return await copySelection()
    }

    /// Electron apps (Claude, Codex) build their accessibility tree only when asked, through AXManualAccessibility.
    static func accessibilitySelection() -> String? {
        if let app = NSWorkspace.shared.frontmostApplication {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                         "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    /// Presses ⌘C in the frontmost app, reads what it copied, then puts the clipboard back as it was.
    @MainActor static func copySelection() async -> String? {
        // The shortcut's own modifiers would turn ⌘C into ⌃⌥⌘C; wait for them to be released.
        for _ in 0..<20 where !NSEvent.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let board = NSPasteboard.general
        let saved: [NSPasteboardItem] = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let before = board.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if board.changeCount != before {
                text = board.string(forType: .string)
                break
            }
        }
        if board.changeCount != before {
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
        return text
    }
}
```

- [ ] **Step 3: Register the hotkey in `AppDelegate`**

Add `private var hotKey: HotKey?`, and after the `SelectionService` registration:

```swift
        hotKey = HotKey.speakSelection { [weak self] in self?.speakFrontmostSelection() }
```

Add to the Speech section:

```swift
    private func speakFrontmostSelection() {
        if speech.isActive {
            speech.stop()
            return
        }
        guard SelectionReader.isTrusted else {
            if prefs.speechAccessExplained {
                speech.fail("This app needs Accessibility to read selections — Settings › Voice")
            } else {
                prefs.speechAccessExplained = true
                let alert = NSAlert()
                alert.messageText = "Let Ambient read your selection"
                alert.informativeText = "To read the text you select in Claude, Codex or a terminal, Ambient needs Accessibility access. It reads only the selection, and only when you press the shortcut. You can also use Services › Speak with Ambient, which needs no permission."
                alert.addButton(withTitle: "Open Accessibility Settings")
                alert.addButton(withTitle: "Not Now")
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn { SelectionReader.askForAccess() }
            }
            return
        }
        Task { @MainActor [weak self] in
            let text = await SelectionReader.selectedText()
            self?.speech.toggle(text)
        }
    }
```

Note the hotkey always stops when speaking; to read a new selection mid-speech, press it twice. The Services route (Task 8) keeps the replace behavior.

- [ ] **Step 4: Remove the Services shortcut**

Delete the `NSKeyEquivalent` key and its `<dict>` from the `NSServices` entry in `Resources/Info.plist`.

- [ ] **Step 5: Build, run, check by hand**

Run: `scripts/build-app.sh --run`

Check: in Claude desktop, Codex, Terminal and iTerm2, select text and press ⌃⌥⌘S. The first time, the explanation appears; grant Accessibility to the dev build, then press again: it reads. Afterwards, check the clipboard (`pbpaste`) still holds what it held before.

- [ ] **Step 6: Commit**

```bash
git add Sources/AmbientApp/Speech/HotKey.swift Sources/AmbientApp/Speech/SelectionReader.swift Sources/AmbientApp/AppDelegate.swift Resources/Info.plist
git commit -m "feat(speech): ⌃⌥⌘S reads the selection through Accessibility"
```

---

### Task 10: Show it — island row, menu bar, pet

**Files:**
- Create: `Sources/AmbientApp/Speech/SpeechRow.swift`
- Modify: `Sources/AmbientApp/Island/IslandViewModel.swift`, `IslandView.swift`, `IslandController.swift`
- Modify: `Sources/AmbientApp/MenuBarController.swift`
- Modify: `Sources/AmbientApp/Pet/PetViewModel.swift`, `PetView.swift`, `PetController.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift` (pass `speech` in)

**Interfaces:**
- Consumes: `SpeechController.state`, `.level`, `.stop()`, `.useMacVoice()`.
- Produces: `IslandViewModel.Presentation.speech`; `IslandViewModel.speech`, `.speechLevel`, `.onStopSpeech`, `.onUseMacVoice`; `PetViewModel.speaking`, `.speechLevel`, `.onStopSpeech`; `struct SpeechRow: View`; `struct LevelMeter: View`.

- [ ] **Step 1: Write `SpeechRow.swift`**

```swift
import SwiftUI

/// "Speaking" with a level meter and a stop button, or why reading aloud failed.
struct SpeechRow: View {
    let state: SpeechState
    let level: Float
    let onStop: () -> Void
    let onUseMacVoice: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(failed ? Color.orange : Color.white)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 8)
            switch state {
            case .preparing, .speaking:
                LevelMeter(level: state == .speaking ? level : 0)
                Button(action: onStop) {
                    Image(systemName: "stop.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Stop speaking")
            case .failed(_, let offerMacVoice) where offerMacVoice:
                Button("Use Mac voice", action: onUseMacVoice)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 40)
        .accessibilityElement(children: .contain)
    }

    private var failed: Bool { if case .failed = state { true } else { false } }

    private var icon: String { failed ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill" }

    private var title: String {
        switch state {
        case .idle: ""
        case .preparing: "Getting ready…"
        case .speaking: "Speaking"
        case .failed(let message, _): message
        }
    }
}

/// Five bars that follow the voice's loudness.
struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let weight: Float = [0.5, 0.8, 1, 0.8, 0.5][i]
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 3, height: CGFloat(4 + 14 * min(1, level * weight)))
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Island model**

In `IslandViewModel`: add `case speech` to `Presentation` (after `bloom`), and add:

```swift
    @Published var speech: SpeechState = .idle
    @Published var speechLevel: Float = 0
    var onStopSpeech: () -> Void = {}
    var onUseMacVoice: () -> Void = {}
```

In `size(for:)` add:

```swift
        case .speech: return CGSize(width: max(collapsed, 360), height: h + 48)
```

- [ ] **Step 3: Island view**

In `IslandView.expandedLike`, change the first case to `case .bloom, .expanded, .speech: true`. In `content`, add before `case .expanded:`:

```swift
        case .speech:
            VStack(spacing: 0) {
                Color.clear.frame(height: model.geometry.notchHeight)
                SpeechRow(state: model.speech, level: model.speechLevel,
                          onStop: model.onStopSpeech, onUseMacVoice: model.onUseMacVoice)
            }
            .transition(.opacity)
```

- [ ] **Step 4: Island controller**

Change `IslandController.init` to take `speech: SpeechController` (store it as `private let speech: SpeechController`) and set `viewModel.onStopSpeech = { [weak speech] in speech?.stop() }` and `viewModel.onUseMacVoice = { [weak speech] in speech?.useMacVoice() }` where the other `viewModel.on…` closures are set. In `start()`, add:

```swift
        speech.$state
            .sink { [weak self] state in
                self?.viewModel.speech = state
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
        speech.$level
            .sink { [weak self] in self?.viewModel.speechLevel = $0 }
            .store(in: &cancellables)
```

In `refresh()`, insert after the `hovering` branch:

```swift
        } else if viewModel.speech != .idle {
            next = .speech
```

- [ ] **Step 5: Menu bar**

Change `MenuBarController.init` to take `speech: SpeechController` (stored as `private let speech: SpeechController`). In `start()`, change the subscription to also refresh on speech:

```swift
        model.$sessions
            .combineLatest(prefs.$quietUntil, speech.$state)
            .sink { [weak self] _, _, _ in DispatchQueue.main.async { self?.updateIcon() } }
            .store(in: &cancellables)
```

At the top of `updateIcon()`, after `guard let button`:

```swift
        switch speech.state {
        case .preparing, .speaking:
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Ambient is reading aloud")
            button.title = ""
            return
        case .failed:
            button.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: "Ambient couldn't read aloud")
            button.title = ""
            return
        case .idle:
            break
        }
```

At the top of `menuNeedsUpdate(_:)`, after `menu.removeAllItems()`:

```swift
        switch speech.state {
        case .preparing, .speaking:
            menu.addItem(item("Stop Speaking", #selector(stopSpeaking)))
            menu.addItem(.separator())
        case .failed(let message, let offerMacVoice):
            menu.addItem(NSMenuItem(title: message, action: nil, keyEquivalent: ""))
            if offerMacVoice { menu.addItem(item("Use Mac Voice", #selector(useMacVoice))) }
            menu.addItem(.separator())
        case .idle:
            break
        }
```

and the actions:

```swift
    @objc private func stopSpeaking() { speech.stop() }
    @objc private func useMacVoice() { speech.useMacVoice() }
```

- [ ] **Step 6: Pet**

In `PetViewModel`, add:

```swift
    @Published var speaking = false
    @Published var speechLevel: Float = 0
    var onStopSpeech: () -> Void = {}
```

In `contentRect`, change `} else if primary != nil {` to `} else if speaking || primary != nil {`. In `contentKind`, add `if speaking { return "speaking" }` after the `peekPinned` line.

In `PetView.content`, add before `} else if let s = model.primary {`:

```swift
            } else if model.speaking {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill").accessibilityHidden(true)
                    Text("Reading aloud").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    LevelMeter(level: model.speechLevel)
                    Button(action: model.onStopSpeech) { Image(systemName: "stop.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop speaking")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
```

Change `PetController.init` to take `speech: SpeechController` (stored as `private let speech: SpeechController`), set `viewModel.onStopSpeech = { [weak speech] in speech?.stop() }`, and in `start()` add:

```swift
        speech.$state
            .sink { [weak self] state in
                self?.viewModel.speaking = state == .preparing || state == .speaking
                self?.trackPointer()
            }
            .store(in: &cancellables)
        speech.$level
            .sink { [weak self] in self?.viewModel.speechLevel = $0 }
            .store(in: &cancellables)
```

- [ ] **Step 7: Pass `speech` in from `AppDelegate`**

Update the three constructions: `IslandController(model: model, prefs: prefs, speech: speech) {…}`, `PetController(model: model, prefs: prefs, speech: speech) {…}`, `MenuBarController(model: model, prefs: prefs, speech: speech, onSettings: …, onDemo: …)`.

- [ ] **Step 8: Build, run, check by hand**

Run: `swift build && scripts/build-app.sh --run`

Check: read a long selection. The island opens to "Getting ready…" then "Speaking" with moving bars, and its stop button stops. Turn the island off in Settings: the menu bar icon becomes a speaker, and its menu starts with "Stop Speaking". Turn the pet on: its bubble says "Reading aloud" with a stop button. Press the shortcut with nothing selected: the island shows "Select some text first" for 5 s. Check with VoiceOver that the stop button reads "Stop speaking".

- [ ] **Step 9: Commit**

```bash
git add Sources/AmbientApp
git commit -m "feat(speech): show reading aloud in the island, menu bar and pet, with stop"
```

---

### Task 11: Online voices — Keychain and `OnlineVoice`

**Files:**
- Create: `Sources/AmbientApp/Speech/KeychainStore.swift`
- Create: `Sources/AmbientApp/Speech/OnlineVoice.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift` (`engine(for:)`)

**Interfaces:**
- Consumes: `OnlineSpeech.request`, `.samples(pcm16:)`, `.failure`, `OnlineProvider`, `PCM.mono`, `SpeechFailure`.
- Produces: `enum KeychainStore { static func key(for: OnlineProvider) -> String?; static func setKey(_: String, for: OnlineProvider) throws; static func deleteKey(for: OnlineProvider) }`; `final class OnlineVoice: SpeechEngine { static func make(prefs: Preferences) throws -> OnlineVoice }`

- [ ] **Step 1: Write `KeychainStore.swift`**

```swift
import AmbientCore
import Foundation
import Security

/// API keys for online voices, in the login Keychain. Never in files or preferences.
enum KeychainStore {
    static let service = "com.viveky259259.Ambient.voice"

    private static func query(_ provider: OnlineProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    static func key(for provider: OnlineProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setKey(_ key: String, for provider: OnlineProvider) throws {
        deleteKey(for: provider)
        var q = query(provider)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SpeechFailure(message: "Couldn't save the key to the Keychain (\(status)).")
        }
    }

    static func deleteKey(for provider: OnlineProvider) {
        SecItemDelete(query(provider) as CFDictionary)
    }
}
```

- [ ] **Step 2: Write `OnlineVoice.swift`**

```swift
import AmbientCore
import Foundation

/// OpenAI, ElevenLabs or an OpenAI-compatible server. The text of each chunk is sent to that service.
final class OnlineVoice: SpeechEngine {
    private let provider: OnlineProvider
    private let baseURL: String
    private let key: String
    private let model: String
    private let voice: String
    private let speed: Double

    init(provider: OnlineProvider, baseURL: String, key: String, model: String, voice: String, speed: Double) {
        self.provider = provider
        self.baseURL = baseURL
        self.key = key
        self.model = model
        self.voice = voice
        self.speed = speed
    }

    static func make(prefs: Preferences) throws -> OnlineVoice {
        let provider = prefs.provider
        let key = KeychainStore.key(for: provider) ?? ""
        if provider.needsKey, key.isEmpty {
            throw SpeechFailure(message: "Add your \(provider.displayName) API key in Settings › Voice.", offerMacVoice: true)
        }
        return OnlineVoice(provider: provider, baseURL: prefs.onlineBaseURL, key: key, model: prefs.onlineModel,
                           voice: prefs.onlineVoice, speed: prefs.speechRate)
    }

    func audio(for text: String) async throws -> PCM {
        guard let request = OnlineSpeech.request(provider: provider, baseURL: baseURL, key: key, model: model,
                                                 voice: voice, text: text, speed: speed) else {
            throw SpeechFailure(message: "Check the online voice's settings in Settings › Voice.", offerMacVoice: true)
        }
        let name = provider.displayName
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                throw SpeechFailure(message: "You're offline, so \(name) can't be reached.", offerMacVoice: true)
            case .timedOut:
                throw SpeechFailure(message: "\(name) took too long to answer.", offerMacVoice: true)
            default:
                throw SpeechFailure(message: "Couldn't reach \(name): \(error.localizedDescription)", offerMacVoice: true)
            }
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SpeechFailure(message: OnlineSpeech.failure(status: status, body: data, provider: provider), offerMacVoice: true)
        }
        return try PCM.mono(OnlineSpeech.samples(pcm16: data), sampleRate: OnlineSpeech.sampleRate)
    }
}
```

- [ ] **Step 3: Use it in `AppDelegate.engine(for:)`**

```swift
        case .online:
            return try OnlineVoice.make(prefs: prefs)
        case .kokoro:
            throw SpeechFailure(message: "\(kind.displayName) isn't set up yet.", offerMacVoice: true)
```

- [ ] **Step 4: Check by hand**

Run: `scripts/build-app.sh --run`

With your OpenAI key, run once in Terminal (this writes to your Keychain under Ambient's service):

```bash
security add-generic-password -s com.viveky259259.Ambient.voice -a openAI -w "$OPENAI_API_KEY" -U
```

```bash
defaults write com.viveky259259.Ambient speechEngine online
```

Relaunch, select text, press the shortcut: it reads with OpenAI's voice. Then:
- turn off Wi-Fi and press it: the island says "You're offline, so OpenAI can't be reached." with **Use Mac voice**.
- run `security add-generic-password -s com.viveky259259.Ambient.voice -a openAI -w bad -U` and press it: "OpenAI didn't accept the API key."
- if you run Kokoro-FastAPI locally, set `onlineProvider` to `custom` and check it reads.

Finally: `security delete-generic-password -s com.viveky259259.Ambient.voice -a openAI` and `defaults delete com.viveky259259.Ambient speechEngine`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientApp/Speech/KeychainStore.swift Sources/AmbientApp/Speech/OnlineVoice.swift Sources/AmbientApp/AppDelegate.swift
git commit -m "feat(speech): online voices from OpenAI, ElevenLabs or your own server, keys in the Keychain"
```

---

### Task 12: The `ambient-voice` helper package

**Files:**
- Create: `Voice/Package.swift`
- Create: `Voice/Sources/ambient-voice/main.swift`
- Create: `scripts/build-voice.sh`
- Create: `scripts/fetch-voice-pack.sh`
- Create: `scripts/smoke-voice.sh`
- Modify: `.gitignore` (add `Voice/.build/`)

**Interfaces:**
- Consumes: `AmbientCore.VoiceWire` (via a local path dependency on the root package).
- Produces: `build/ambient-voice/ambient-voice <pack folder>` speaking `VoiceWire`; `dist/ambient-voice-<version>.zip` containing the `ambient-voice/` folder.

- [ ] **Step 1: Write `Voice/Package.swift`**

```swift
// swift-tools-version:6.2
import PackageDescription

// The offline voice helper. Separate from Ambient's own package so that Ambient keeps no dependencies; it's
// downloaded only by people who choose the offline voice.
let package = Package(
    name: "AmbientVoice",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "Ambient", path: ".."),
        .package(url: "https://github.com/mlalma/kokoro-ios.git", exact: "1.0.11"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .executableTarget(
            name: "ambient-voice",
            dependencies: [
                .product(name: "AmbientCore", package: "Ambient"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write `Voice/Sources/ambient-voice/main.swift`**

```swift
import AmbientCore
import Foundation
import KokoroSwift
import MLX

// ambient-voice <pack folder>
//
// Reads VoiceWire requests on stdin, one JSON line each, and answers each on stdout with a header line and float32
// PCM frames. Loads the model once. Exits when stdin closes.

struct HelperError: Error, CustomStringConvertible {
    let description: String
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: ambient-voice <pack folder>\n".utf8))
    exit(64)
}
let pack = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let tts = KokoroTTS(modelPath: pack.appendingPathComponent("kokoro-v1_0.safetensors"))
let out = FileHandle.standardOutput
var voices: [String: MLXArray] = [:]

func voice(_ id: String) throws -> MLXArray {
    if let v = voices[id] { return v }
    guard id.range(of: "^[a-z]{2}_[a-z]{1,20}$", options: .regularExpression) != nil else {
        throw HelperError(description: "unknown voice \(id)")
    }
    let arrays = try MLX.loadArrays(url: pack.appendingPathComponent("voices/\(id).safetensors"))
    guard let v = arrays.values.first else { throw HelperError(description: "voice \(id) is empty") }
    voices[id] = v
    return v
}

while let line = readLine(strippingNewline: true) {
    guard let request = VoiceWire.request(from: Data(line.utf8)) else { continue }
    do {
        let language: Language = request.voice.hasPrefix("b") ? .enGB : .enUS
        let (samples, _) = try tts.generateAudio(voice: try voice(request.voice), language: language,
                                                 text: request.text, speed: Float(request.speed))
        out.write(VoiceWire.line(VoiceWire.Header(id: request.id, sampleRate: KokoroTTS.Constants.samplingRate)))
        var i = 0
        while i < samples.count {
            let end = min(i + KokoroTTS.Constants.samplingRate, samples.count)
            out.write(VoiceWire.frame(Array(samples[i..<end])))
            i = end
        }
        out.write(VoiceWire.end)
    } catch {
        out.write(VoiceWire.line(VoiceWire.Header(id: request.id, error: "\(error)")))
    }
}
```

- [ ] **Step 3: Write `scripts/fetch-voice-pack.sh`**

```zsh
#!/bin/zsh
# Downloads the offline voice's model files into a folder and checks every hash, for building and testing the
# helper without going through the app.
#
#   scripts/fetch-voice-pack.sh build/voice-pack
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=${1:?usage: scripts/fetch-voice-pack.sh <folder>}
mkdir -p "$DEST/voices"
swift run -q ambient voice-files | while read -r path url sha; do
  file="$DEST/$path"
  if [[ ! -f $file ]] || [[ $(shasum -a 256 "$file" | cut -d' ' -f1) != "$sha" ]]; then
    echo "Downloading $path"
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  [[ $(shasum -a 256 "$file" | cut -d' ' -f1) == "$sha" ]] || { echo "Hash mismatch: $path" >&2; exit 1; }
done
echo "Voice pack ready in $DEST"
```

- [ ] **Step 4: Write `scripts/build-voice.sh`**

```zsh
#!/bin/zsh
# Builds the offline voice helper into build/ambient-voice/ and zips it as dist/ambient-voice-<version>.zip.
#
#   scripts/build-voice.sh                       ad-hoc signed, for local testing
#   scripts/build-voice.sh --sign <SHA-1>        Developer ID, hardened runtime
#   NOTARY_PROFILE=… scripts/build-voice.sh --sign <SHA-1> --notarize
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="-" NOTARIZE=0
while (( $# )); do
  case "$1" in
    --sign) SIGN_ID="$2"; shift ;;
    --notarize) NOTARIZE=1 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/AmbientCore/Speech/VoicePackPin.swift)
DD=build/voice-dd
# MLX's Metal shaders are compiled only by Xcode's build system, not by `swift build`.
(cd Voice && xcodebuild -scheme ambient-voice -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "../$DD" -skipPackagePluginValidation -skipMacroValidation build) | tail -3
PRODUCTS=$DD/Build/Products/Release

OUT=build/ambient-voice
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$PRODUCTS/ambient-voice" "$OUT/"
# SwiftPM resource bundles (MLX's metallib, Kokoro's config, Misaki's lexicons) are found next to the executable.
for b in "$PRODUCTS"/*.bundle(N); do cp -R "$b" "$OUT/"; done
if [[ -d $PRODUCTS/PackageFrameworks ]]; then
  mkdir -p "$OUT/Frameworks"
  cp -R "$PRODUCTS"/PackageFrameworks/*.framework "$OUT/Frameworks/"
  install_name_tool -add_rpath @executable_path/Frameworks "$OUT/ambient-voice" 2>/dev/null || true
fi

SIGN_FLAGS=(--force --sign "$SIGN_ID")
[[ $SIGN_ID != "-" ]] && SIGN_FLAGS+=(--options runtime --timestamp)
for f in "$OUT"/Frameworks/*.framework(N); do codesign "${SIGN_FLAGS[@]}" "$f"; done
codesign "${SIGN_FLAGS[@]}" --identifier com.viveky259259.Ambient.voice "$OUT/ambient-voice"
codesign --verify --strict "$OUT/ambient-voice"

mkdir -p dist
ZIP=dist/ambient-voice-$VERSION.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$OUT" "$ZIP"
if (( NOTARIZE )); then
  xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE}" --wait --timeout 30m
fi
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1), sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1), signed: $SIGN_ID)"
```

- [ ] **Step 5: Write `scripts/smoke-voice.sh`**

```zsh
#!/bin/zsh
# Runs build/ambient-voice once from another folder and checks that it answers with at least a second of audio.
#
#   scripts/smoke-voice.sh build/voice-pack
set -euo pipefail
cd "$(dirname "$0")/.."
PACK=$(cd "${1:?usage: scripts/smoke-voice.sh <pack folder>}" && pwd)
HELPER=$PWD/build/ambient-voice/ambient-voice
OUT=$PWD/build/voice-smoke.bin
printf '%s\n' '{"id":"smoke","speed":1,"text":"Hello from Ambient. This is the offline voice.","voice":"af_heart"}' \
  | (cd / && "$HELPER" "$PACK") > "$OUT"
python3 -I - "$OUT" <<'EOF'
import json, struct, sys
data = open(sys.argv[1], "rb").read()
header, rest = data.split(b"\n", 1)
h = json.loads(header)
assert "error" not in h, h
assert h["sampleRate"] == 24000, h
samples = 0
while True:
    (n,) = struct.unpack("<I", rest[:4]); rest = rest[4:]
    if n == 0: break
    samples += n // 4; rest = rest[n:]
assert samples >= 24000, samples
print(f"ok: {samples / 24000:.1f} s of audio")
EOF
```

- [ ] **Step 6: Ignore the helper's build folder and make the scripts executable**

Append `Voice/.build/` to `.gitignore`, then:

Run: `chmod +x scripts/build-voice.sh scripts/fetch-voice-pack.sh scripts/smoke-voice.sh`

- [ ] **Step 7: Build and smoke-test**

Run: `scripts/fetch-voice-pack.sh build/voice-pack`
Expected: downloads about 330 MB, ends with `Voice pack ready in build/voice-pack`.

Run: `scripts/build-voice.sh`
Expected: `Built dist/ambient-voice-1.zip (…, sha256 …, signed: -)`.

Run: `ls build/ambient-voice && otool -L build/ambient-voice/ambient-voice | head`
Expected: the executable, `*.bundle` folders including `mlx-swift_Cmlx.bundle`, and a `Frameworks` folder if any library is dynamic. Every `@rpath/…` that `otool -L` lists must exist under `build/ambient-voice/Frameworks`. If one is elsewhere in `$PRODUCTS`, add a `cp` for it to `build-voice.sh` and rebuild.

Run: `scripts/smoke-voice.sh build/voice-pack`
Expected: `ok: N.N s of audio` with N ≥ 1.

If it fails with a voice shape error from kokoro-ios, the per-voice safetensors don't match what `generateAudio` expects. In that case, switch the voices to `voices.npz` from `mlalma/KokoroTestApp` (Apache-2.0): pin its SHA-256 in `VoicePackManifest` and load it with `NpyzReader.read(fileFromPath:)` from MLXUtilsLibrary, keyed `"<id>.npy"`, and update Task 7's tests to match.

Run: `afplay` on the audio to hear it:

```bash
python3 -I -c "
import struct,sys,wave
d=open('build/voice-smoke.bin','rb').read(); h,r=d.split(b'\n',1); s=b''
while True:
  (n,)=struct.unpack('<I',r[:4]); r=r[4:]
  if n==0: break
  f=struct.unpack('<%df'%(n//4),r[:n]); r=r[n:]; s+=b''.join(struct.pack('<h',max(-32768,min(32767,int(x*32767)))) for x in f)
w=wave.open('build/voice-smoke.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(s); w.close()"
```

```bash
afplay build/voice-smoke.wav
```

Expected: you hear "Hello from Ambient. This is the offline voice."

- [ ] **Step 8: Commit**

```bash
git add Voice/Package.swift Voice/Package.resolved Voice/Sources scripts/build-voice.sh scripts/fetch-voice-pack.sh scripts/smoke-voice.sh .gitignore
git commit -m "feat(voice): the ambient-voice helper running Kokoro offline, with build and smoke-test scripts"
```

---

### Task 13: Offline voice in the app — installer and `KokoroVoice`

**Files:**
- Create: `Sources/AmbientApp/Speech/VoicePackInstaller.swift`
- Create: `Sources/AmbientApp/Speech/FileDownload.swift`
- Create: `Sources/AmbientApp/Speech/KokoroVoice.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `VoicePackManifest.current`, `FileHash.sha256`, `AmbientPaths.voice`, `VoiceWire`, `PCM.mono`, `SpeechFailure`.
- Produces:
  - `final class VoicePackInstaller: ObservableObject` (main thread) with `enum Status: Equatable { case unsupported(String), unavailable, notInstalled, downloading(Double), installed, failed(String) }`, `status`, `folder: URL`, `helper: URL`, `install()`, `cancel()`, `remove()`, `refresh()`
  - `final class KokoroVoice: SpeechEngine` with `init(helper: URL, pack: URL, log: URL)`, `var voice: String`, `var speed: Double`, `func shutDown()`

- [ ] **Step 1: Write `FileDownload.swift`**

```swift
import Foundation

/// Downloads one file to a path, reporting bytes written. Cancelling the calling task cancels the download.
final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var moveError: Error?

    private init(destination: URL, progress: @escaping (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func run(_ url: URL, to destination: URL, progress: @escaping (Int64) -> Void) async throws {
        let download = FileDownload(destination: destination, progress: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                download.start(url, c)
            }
        } onCancel: {
            download.cancel()
        }
    }

    private func start(_ url: URL, _ c: CheckedContinuation<Void, Error>) {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        lock.lock()
        continuation = c
        task = session.downloadTask(with: url)
        lock.unlock()
        task?.resume()
        session.finishTasksAndInvalidate()
    }

    private func cancel() {
        lock.lock(); defer { lock.unlock() }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "The server answered \(status)."])
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        if let error = error ?? moveError {
            c?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else {
            c?.resume()
        }
    }
}
```

- [ ] **Step 2: Write `VoicePackInstaller.swift`**

```swift
import AmbientCore
import Foundation
import Security

/// Downloads, checks and installs the offline voice, and removes it. Nothing reaches the pack folder unless every
/// hash matched and the helper is signed by Ambient's team. Used from the main thread; the download hops back to it.
final class VoicePackInstaller: ObservableObject {
    enum Status: Equatable {
        case unsupported(String)
        /// This build has no published helper pinned.
        case unavailable
        case notInstalled
        case downloading(Double)
        case installed
        case failed(String)
    }

    @Published private(set) var status: Status = .notInstalled
    let manifest: VoicePackManifest
    private let paths: AmbientPaths
    private var work: Task<Void, Never>?

    init(paths: AmbientPaths, manifest: VoicePackManifest = .current) {
        self.paths = paths
        self.manifest = manifest
        refresh()
    }

    var folder: URL {
        #if AMBIENT_DEV
        if let dev = ProcessInfo.processInfo.environment["AMBIENT_VOICE_DEV_PACK"] { return URL(fileURLWithPath: dev) }
        #endif
        return paths.voice.appendingPathComponent(manifest.folderName, isDirectory: true)
    }

    var helper: URL {
        #if AMBIENT_DEV
        if let dev = ProcessInfo.processInfo.environment["AMBIENT_VOICE_DEV_HELPER"] { return URL(fileURLWithPath: dev) }
        #endif
        return folder.appendingPathComponent("ambient-voice/ambient-voice")
    }

    var downloadSize: String {
        "≈\(Int((Double(manifest.totalBytes) / 1_000_000).rounded())) MB"
    }

    func refresh() {
        guard work == nil else { return }
        var arm = false
        #if arch(arm64)
        arm = true
        #endif
        switch manifest.support(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, isAppleSilicon: arm) {
        case .needsAppleSilicon:
            status = .unsupported("The offline model needs a Mac with Apple silicon.")
        case .needsNewerMacOS(let v):
            status = .unsupported("The offline model needs macOS \(v) or later.")
        case .supported:
            if FileManager.default.isExecutableFile(atPath: helper.path) {
                status = .installed
            } else {
                status = manifest.isPublished ? .notInstalled : .unavailable
            }
        }
    }

    func install() {
        guard work == nil, status == .notInstalled || isFailed else { return }
        status = .downloading(0)
        work = Task { [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        work?.cancel()
    }

    func remove() {
        cancel()
        try? FileManager.default.removeItem(at: paths.voice.appendingPathComponent(manifest.folderName))
        refresh()
    }

    private var isFailed: Bool { if case .failed = status { true } else { false } }

    private func run() async {
        let fm = FileManager.default
        let staging = paths.voice.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let total = Double(manifest.totalBytes)
            var done: Int64 = 0
            for file in [manifest.helper] + manifest.files {
                let destination = staging.appendingPathComponent(file.path)
                let base = done
                try await FileDownload.run(file.url, to: destination) { [weak self] written in
                    let fraction = min(1, Double(base + written) / total)
                    DispatchQueue.main.async { self?.status = .downloading(fraction) }
                }
                guard try FileHash.sha256(of: destination) == file.sha256 else {
                    throw SpeechFailure(message: "A downloaded file didn't match, so nothing was installed. Try again.")
                }
                done += file.bytes
            }
            let zip = staging.appendingPathComponent(manifest.helper.path)
            try Self.unzip(zip, into: staging)
            try fm.removeItem(at: zip)
            try Self.verifySignature(staging.appendingPathComponent("ambient-voice/ambient-voice"), team: manifest.teamID)
            let target = paths.voice.appendingPathComponent(manifest.folderName, isDirectory: true)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging, to: target)
            await MainActor.run { self.work = nil; self.refresh() }
        } catch is CancellationError {
            await MainActor.run { self.work = nil; self.refresh() }
        } catch {
            let message = (error as? SpeechFailure)?.message ?? "The download failed: \(error.localizedDescription)"
            await MainActor.run { self.work = nil; self.status = .failed(message) }
        }
    }

    private static func unzip(_ zip: URL, into folder: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, folder.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw SpeechFailure(message: "Couldn't unpack the offline voice.") }
    }

    private static func verifySignature(_ url: URL, team: String) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
                                         requirement) == errSecSuccess else {
            throw SpeechFailure(message: "The offline voice's signature didn't check out, so nothing was installed.")
        }
    }
}
```

- [ ] **Step 3: Write `KokoroVoice.swift`**

```swift
import AmbientCore
import Foundation

/// The offline Kokoro model, in the `ambient-voice` helper. One helper process serves every request in turn and is
/// kept alive between selections so the model loads once; it's ended after 5 idle minutes.
final class KokoroVoice: SpeechEngine {
    private let helper: URL
    private let pack: URL
    private let log: URL
    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.kokoro")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var idle: DispatchWorkItem?
    private var nextID = 0
    var voice: String
    var speed: Double

    static let idleTimeout: TimeInterval = 300

    init(helper: URL, pack: URL, log: URL, voice: String, speed: Double) {
        self.helper = helper
        self.pack = pack
        self.log = log
        self.voice = voice
        self.speed = speed
    }

    /// Results of a cancelled request are simply dropped by the pipeline, so the helper isn't interrupted.
    func audio(for text: String) async throws -> PCM {
        let voice = self.voice, speed = self.speed
        return try await withCheckedThrowingContinuation { c in
            queue.async {
                c.resume(with: Result { try self.synthesize(text, voice: voice, speed: speed) })
            }
        }
    }

    func shutDown() {
        queue.async { self.stopProcess() }
    }

    private func synthesize(_ text: String, voice: String, speed: Double) throws -> PCM {
        idle?.cancel()
        defer { scheduleIdleExit() }
        try startIfNeeded()
        guard let input, let output else { throw stopped() }
        nextID += 1
        let id = String(nextID)
        do {
            try input.write(contentsOf: VoiceWire.line(VoiceWire.Request(id: id, text: text, voice: voice, speed: speed)))
        } catch {
            stopProcess()
            throw stopped()
        }
        var reader = VoiceWire.Reader()
        var samples: [Float] = []
        var sampleRate = 24_000
        while true {
            let data = output.availableData
            if data.isEmpty {
                stopProcess()
                throw stopped()
            }
            let events: [VoiceWire.Event]
            do { events = try reader.feed(data) } catch {
                stopProcess()
                throw stopped()
            }
            for event in events {
                switch event {
                case .header(let header):
                    if let error = header.error {
                        throw SpeechFailure(message: "The offline voice couldn't read that (\(error)).", offerMacVoice: true)
                    }
                    guard header.id == id else {
                        stopProcess()
                        throw stopped()
                    }
                    sampleRate = header.sampleRate ?? sampleRate
                case .samples(let s):
                    samples += s
                case .end:
                    return try PCM.mono(samples, sampleRate: sampleRate)
                }
            }
        }
    }

    private func startIfNeeded() throws {
        if let process, process.isRunning { return }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw SpeechFailure(message: "The offline voice isn't installed. Download it in Settings › Voice.", offerMacVoice: true)
        }
        let p = Process()
        p.executableURL = helper
        p.arguments = [pack.path]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        FileManager.default.createFile(atPath: log.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: log)) ?? FileHandle.nullDevice
        do { try p.run() } catch { throw stopped() }
        process = p
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
    }

    private func stopProcess() {
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
        output = nil
    }

    private func scheduleIdleExit() {
        let work = DispatchWorkItem { [weak self] in self?.stopProcess() }
        idle = work
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: work)
    }

    private func stopped() -> SpeechFailure {
        SpeechFailure(message: "Offline voice stopped", offerMacVoice: true)
    }
}
```

- [ ] **Step 4: Wire into `AppDelegate`**

Add properties:

```swift
    private lazy var voicePack = VoicePackInstaller(paths: paths)
    private var kokoro: KokoroVoice?
```

Replace the `.kokoro` case in `engine(for:)`:

```swift
        case .kokoro:
            guard voicePack.status == .installed else {
                throw SpeechFailure(message: "The offline voice isn't installed. Download it in Settings › Voice.", offerMacVoice: true)
            }
            let engine = kokoro ?? KokoroVoice(helper: voicePack.helper, pack: voicePack.folder,
                                               log: paths.logs.appendingPathComponent("voice.log"),
                                               voice: prefs.kokoroVoice, speed: prefs.speechRate)
            engine.voice = prefs.kokoroVoice
            engine.speed = prefs.speechRate
            kokoro = engine
            return engine
```

In `applicationWillTerminate`, add `kokoro?.shutDown()`.

- [ ] **Step 5: Check by hand with the dev helper**

Run: `swift build && scripts/build-app.sh` (an ad-hoc dev build, so `AMBIENT_DEV` is set and the dev overrides work)

```bash
pkill -x Ambient; defaults write com.viveky259259.Ambient speechEngine kokoro
```

```bash
AMBIENT_VOICE_DEV_HELPER=$PWD/build/ambient-voice/ambient-voice AMBIENT_VOICE_DEV_PACK=$PWD/build/voice-pack build/Ambient.app/Contents/MacOS/Ambient
```

Check: select a long reply and press the shortcut. The first chunk takes a moment (model load), later chunks follow without gaps. Press again: it stops. `ps aux | grep ambient-voice` shows one helper; it's gone 5 minutes after the last use. Run `pkill -f build/ambient-voice/ambient-voice` while it speaks: the island shows "Offline voice stopped" with **Use Mac voice**, and the next press starts a fresh helper.

Then `defaults delete com.viveky259259.Ambient speechEngine`.

- [ ] **Step 6: Commit**

```bash
git add Sources/AmbientApp/Speech Sources/AmbientApp/AppDelegate.swift
git commit -m "feat(speech): the offline Kokoro voice, installed only after its hashes and signature check out"
```

---

### Task 14: The first-run chooser and Settings › Voice

**Files:**
- Create: `Sources/AmbientApp/Speech/VoiceSections.swift` (shared by chooser and pane)
- Create: `Sources/AmbientApp/Speech/VoiceChooser.swift`
- Create: `Sources/AmbientApp/Settings/Panes/VoicePane.swift`
- Modify: `Sources/AmbientApp/Settings/SettingsPane.swift`, `SettingsView.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `Preferences` speech keys, `SpeechController.preview`, `.chooseEngine`, `VoicePackInstaller`, `KeychainStore`, `OnlineProvider`, `SpeechEngineKind`.
- Produces: `struct EngineSection: View`, `final class VoiceChooser` with `func show(completion: @escaping (Bool) -> Void)`, `SettingsPane.voice`, `struct VoicePane: View`.

- [ ] **Step 1: Write `VoiceSections.swift`**

```swift
import AmbientCore
import AVFoundation
import SwiftUI

/// The settings for one engine, shared by the first-run chooser and Settings › Voice.
struct EngineSection: View {
    let kind: SpeechEngineKind
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    @Binding var apiKey: String

    var body: some View {
        switch kind {
        case .mac: macVoice
        case .kokoro: offline
        case .online: online
        }
    }

    private var macVoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Free and offline. Nothing leaves your Mac.").font(.callout).foregroundStyle(.secondary)
            Picker("Voice", selection: $prefs.macVoice) {
                Text("System voice").tag("")
                ForEach(Self.macVoices, id: \.identifier) { v in
                    Text(v.quality == .premium ? "\(v.name) (Premium)" : v.quality == .enhanced ? "\(v.name) (Enhanced)" : v.name)
                        .tag(v.identifier)
                }
            }
            .fixedSize()
            Text("More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kokoro runs on your Mac. Natural, offline, and free after a one-time download.")
                .font(.callout).foregroundStyle(.secondary)
            switch voicePack.status {
            case .unsupported(let reason):
                Text(reason).font(.callout)
            case .unavailable:
                Text("The offline model isn't available in this build of Ambient.").font(.callout)
            case .notInstalled, .failed:
                if case .failed(let message) = voicePack.status { Text(message).font(.callout).foregroundStyle(.orange) }
                Button("Download (\(voicePack.downloadSize))") { voicePack.install() }
            case .downloading(let fraction):
                HStack {
                    ProgressView(value: fraction).frame(width: 180)
                    Text("\(Int(fraction * 100))%").monospacedDigit()
                    Button("Cancel") { voicePack.cancel() }
                }
            case .installed:
                Picker("Voice", selection: $prefs.kokoroVoice) {
                    ForEach(voicePack.manifest.voices) { Text("\($0.name) (\($0.accent))").tag($0.id) }
                }
                .fixedSize()
            }
        }
    }

    private var online: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Service", selection: $prefs.onlineProvider) {
                ForEach(OnlineProvider.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .onChange(of: prefs.onlineProvider) { _, _ in
                prefs.onlineVoice = prefs.provider.defaultVoice
                prefs.onlineModel = prefs.provider.defaultModel
                apiKey = KeychainStore.key(for: prefs.provider) ?? ""
            }
            if prefs.provider == .custom {
                TextField("Server URL", text: $prefs.onlineBaseURL, prompt: Text("http://localhost:8880/v1"))
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            SecureField(prefs.provider.needsKey ? "API key" : "API key (optional)", text: $apiKey)
                .textFieldStyle(.roundedBorder).frame(width: 280)
            HStack {
                TextField("Voice", text: $prefs.onlineVoice).textFieldStyle(.roundedBorder).frame(width: 180)
                TextField("Model", text: $prefs.onlineModel).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            Label("The text you select is sent to \(prefs.provider == .custom ? "your server" : prefs.provider.displayName).",
                  systemImage: "network")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Voices for the user's language, best quality first.
    static var macVoices: [AVSpeechSynthesisVoice] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// Whether this engine can play right now.
    static func ready(_ kind: SpeechEngineKind, prefs: Preferences, voicePack: VoicePackInstaller, apiKey: String) -> Bool {
        switch kind {
        case .mac: true
        case .kokoro: voicePack.status == .installed
        case .online: !prefs.provider.needsKey || !apiKey.isEmpty
        }
    }

    /// Saves a typed key; an emptied field forgets it.
    static func saveKey(_ apiKey: String, prefs: Preferences) {
        if apiKey.isEmpty { KeychainStore.deleteKey(for: prefs.provider) } else { try? KeychainStore.setKey(apiKey, for: prefs.provider) }
    }
}
```

- [ ] **Step 2: Write `VoiceChooser.swift`**

```swift
import AmbientCore
import AppKit
import SwiftUI

/// Asked once, the first time the shortcut is used: which voice reads aloud.
final class VoiceChooser {
    private let prefs: Preferences
    private let voicePack: VoicePackInstaller
    private let speech: SpeechController
    private var window: NSWindow?
    private var completion: ((Bool) -> Void)?

    init(prefs: Preferences, voicePack: VoicePackInstaller, speech: SpeechController) {
        self.prefs = prefs
        self.voicePack = voicePack
        self.speech = speech
    }

    func show(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        if window == nil {
            let view = VoiceChooserView(prefs: prefs, voicePack: voicePack,
                                        onPreview: { [weak self] in self?.speech.preview($0) },
                                        onPlay: { [weak self] kind in self?.finish(kind) },
                                        onCancel: { [weak self] in self?.finish(nil) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Choose a Voice"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.completion?(false)
                self?.completion = nil
            }
            self.window = window
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(_ kind: SpeechEngineKind?) {
        if let kind { prefs.speechEngine = kind.rawValue }
        let done = completion
        completion = nil
        window?.close()
        done?(kind != nil)
    }
}

private struct VoiceChooserView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    let onPreview: (SpeechEngineKind) -> Void
    let onPlay: (SpeechEngineKind) -> Void
    let onCancel: () -> Void

    @State private var kind: SpeechEngineKind = .mac
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How should Ambient read aloud?").font(.title2.weight(.semibold))
            Picker("Voice", selection: $kind) {
                ForEach(SpeechEngineKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            EngineSection(kind: kind, prefs: prefs, voicePack: voicePack, apiKey: $apiKey)
                .frame(minHeight: 120, alignment: .topLeading)
            HStack {
                Button("Preview") {
                    EngineSection.saveKey(apiKey, prefs: prefs)
                    onPreview(kind)
                }
                .disabled(!ready)
                Spacer()
                Text("You can change this in Settings › Voice.").font(.caption).foregroundStyle(.secondary)
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Play") {
                    EngineSection.saveKey(apiKey, prefs: prefs)
                    onPlay(kind)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { apiKey = KeychainStore.key(for: prefs.provider) ?? "" }
    }

    private var ready: Bool { EngineSection.ready(kind, prefs: prefs, voicePack: voicePack, apiKey: apiKey) }
}
```

- [ ] **Step 3: Add the Voice pane to `SettingsPane`**

Add `voice` to the enum's cases after `pet`: `case welcome, agents, island, pet, voice, alerts, dock, wallpaper, performance, general`. Add to `title`: `case .voice: "Voice"`; to `symbol`: `case .voice: "speaker.wave.2"`; to `subtitle`: `case .voice: "Select text in Claude, Codex or a terminal, press the shortcut, and Ambient reads it aloud."`

- [ ] **Step 4: Write `VoicePane.swift`**

```swift
import AmbientCore
import AppKit
import SwiftUI

struct VoicePane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    @ObservedObject var speech: SpeechController
    /// "⌘⇧U" on the Services route, "⌃⌥⌘S" on the hotkey route (Task 1's decision).
    let shortcut: String

    @State private var apiKey = ""

    private var kind: SpeechEngineKind { prefs.speechEngineKind ?? .mac }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .voice)
            SettingsSection(footer: "Also in every app's menu under Services › Speak with Ambient.") {
                SettingsRow(title: "Shortcut", subtitle: "Press it again to stop.") {
                    HStack {
                        Text(shortcut).font(.system(.body, design: .rounded).weight(.semibold))
                        // Services shortcuts are rebound in System Settings › Keyboard › Keyboard Shortcuts › Services.
                        // On the hotkey route (Task 9) leave this button out: ⌃⌥⌘S is fixed in the first release.
                        Button("Change…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                        .buttonStyle(.pill)
                    }
                }
            }
            SettingsSection(footer: nil) {
                SettingsRow(title: "Voice") {
                    Picker("Voice", selection: Binding(get: { kind }, set: { prefs.speechEngine = $0.rawValue })) {
                        ForEach(SpeechEngineKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                EngineSection(kind: kind, prefs: prefs, voicePack: voicePack, apiKey: $apiKey)
                    .padding(.vertical, Theme.Space.xs)
                    .onChange(of: apiKey) { _, key in EngineSection.saveKey(key, prefs: prefs) }
                if kind == .kokoro, voicePack.status == .installed {
                    SettingsDivider()
                    SettingsRow(title: "Offline model", subtitle: voicePack.downloadSize + " on this Mac.") {
                        Button("Remove") { voicePack.remove() }.buttonStyle(.pill)
                    }
                }
            }
            SettingsSection(footer: nil) {
                SettingsRow(title: "Speed") {
                    Slider(value: $prefs.speechRate, in: 0.5...2, step: 0.1).frame(width: 180)
                }
                SettingsDivider()
                SettingsToggleRow(title: "Read code blocks",
                                  subtitle: "Off: a code block is read as \u{201C}code block, 12 lines\u{201D}.",
                                  isOn: $prefs.speechReadsCode)
                SettingsDivider()
                SettingsRow(title: "Try it") {
                    Button(speech.isActive ? "Stop" : "Preview") {
                        speech.isActive ? speech.stop() : speech.preview(kind)
                    }
                    .buttonStyle(.pill)
                    .disabled(!EngineSection.ready(kind, prefs: prefs, voicePack: voicePack, apiKey: apiKey))
                }
            }
        }
        .onAppear {
            apiKey = KeychainStore.key(for: prefs.provider) ?? ""
            voicePack.refresh()
        }
    }
}
```

Check `Design/Components.swift` for the exact signatures of `SettingsSection`, `SettingsRow`, `SettingsToggleRow`, `SettingsDivider` and `.pill`; `PetPane` uses them the same way. If `SettingsSection(footer:)` doesn't take nil, drop the argument for those sections.

- [ ] **Step 5: Show the pane in `SettingsView`**

Add `let speech: SpeechController`, `let voicePack: VoicePackInstaller`, `let shortcut: String` to `SettingsView`, and in `paneContent`:

```swift
        case .voice:
            VoicePane(prefs: prefs, voicePack: voicePack, speech: speech, shortcut: shortcut)
```

In `AppDelegate.showSetup()`, pass `speech: speech, voicePack: voicePack, shortcut: Self.speechShortcut` to `SettingsView`, and add beside the Speech section:

```swift
    /// From Task 1's decision: "⌘⇧U" (or the letter chosen) on the Services route, "⌃⌥⌘S" on the hotkey route.
    static let speechShortcut = "⌘⇧U"
```

- [ ] **Step 6: Use the chooser on first use**

Add `private lazy var voiceChooser = VoiceChooser(prefs: prefs, voicePack: voicePack, speech: speech)` and replace the temporary `speech.chooseEngine` from Task 8 with:

```swift
        speech.chooseEngine = { [weak self] done in self?.voiceChooser.show(completion: done) }
```

- [ ] **Step 7: Check by hand**

Run: `defaults delete com.viveky259259.Ambient speechEngine; scripts/build-app.sh --run`

Check:
1. Select text and press the shortcut: the chooser opens with Mac voice selected. **Preview** reads the sample. **Play** closes it and reads the selection. Press the shortcut again later: no chooser.
2. Reset (`defaults delete …`), choose **Online model**: Play stays disabled until a key is typed, and the network line names the service. Close the window: nothing plays and nothing is saved.
3. Choose **Offline model** on this build: it says the model isn't available in this build (no helper pinned yet). On a macOS 14 machine or VM, it gives the macOS reason.
4. Settings › Voice: switching engines, voices, speed and **Read code blocks** take effect on the next press. Typing an API key and checking `security find-generic-password -s com.viveky259259.Ambient.voice -a openAI` shows it's saved; clearing the field deletes it.
5. VoiceOver reads every control in the chooser and pane.

Run: `swift test`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/AmbientApp
git commit -m "feat(speech): first-run voice chooser and Settings › Voice"
```

---

### Task 15: Publish the voice pack, pin it, and document

Publishing a GitHub release is outward-facing: ask the user before Step 3.

**Files:**
- Create: `scripts/pin-voice-helper.sh`
- Modify: `Sources/AmbientCore/Speech/VoicePackPin.swift` (by the script)
- Modify: `README.md`, `SECURITY.md`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`

- [ ] **Step 1: Write `scripts/pin-voice-helper.sh`**

```zsh
#!/bin/zsh
# Pins a published helper zip into the app: its SHA-256 and size go into VoicePackPin.swift.
#
#   scripts/pin-voice-helper.sh dist/ambient-voice-1.zip
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP=${1:?usage: scripts/pin-voice-helper.sh <zip>}
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
BYTES=$(stat -f %z "$ZIP")
FILE=Sources/AmbientCore/Speech/VoicePackPin.swift
sed -i '' -e "s/helperSHA256 = \".*\"/helperSHA256 = \"$SHA\"/" -e "s/helperBytes: Int64 = .*/helperBytes: Int64 = $BYTES/" "$FILE"
grep -E 'helperSHA256|helperBytes' "$FILE"
```

Run: `chmod +x scripts/pin-voice-helper.sh`

- [ ] **Step 2: Build, sign and notarize the helper**

Run: `NOTARY_PROFILE=MomentumAI scripts/build-voice.sh --sign FFB81B687F8B4F36370612F077A08A414D71138E --notarize`
Expected: notarization `status: Accepted`, then `Built dist/ambient-voice-1.zip (…)`.

Run: `codesign -dv --verbose=2 build/ambient-voice/ambient-voice 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier"`
Expected: `Authority=Developer ID Application: Vivek Yadav (CU3457GT8T)` and `TeamIdentifier=CU3457GT8T`.

Run: `scripts/smoke-voice.sh build/voice-pack`
Expected: `ok: …`.

- [ ] **Step 3: Publish the `voice-1` release (after the user confirms)**

It must not become the "latest" release, which the site's download links follow.

```bash
gh release create voice-1 dist/ambient-voice-1.zip --repo viveky259259/ambient --latest=false --title "Offline voice pack 1" --notes "The ambient-voice helper for Ambient's offline voice (Kokoro-82M via kokoro-ios and MLX). Ambient downloads and verifies it when you choose Offline model in Settings › Voice; you don't need to download it yourself."
```

Run: `gh release view --repo viveky259259/ambient --json tagName -q .tagName`
Expected: still the latest app release (`v0.6.0` or newer), not `voice-1`.

- [ ] **Step 4: Pin it**

Run: `scripts/pin-voice-helper.sh dist/ambient-voice-1.zip`
Expected: the two pinned lines with a 64-character hash and the byte size.

Run: `swift test --filter VoicePackTests`
Expected: PASS.

- [ ] **Step 5: Install from scratch with a Developer ID build**

Run: `rm -rf ~/.ambient/voice && scripts/build-app.sh --sign FFB81B687F8B4F36370612F077A08A414D71138E --run`

Check: Settings › Voice › Offline model › **Download (≈N MB)**: progress runs to 100%, the voice picker appears, `ls ~/.ambient/voice` shows only `kokoro-1` (no `.staging-*`), and Preview speaks. Then **Remove** deletes the folder. Start a download and **Cancel** halfway: no folder is left behind.

- [ ] **Step 6: Documentation**

`README.md`: add a feature bullet after **Desktop pet**:

```markdown
- **Read aloud** — select part of a reply in Claude, Codex or your terminal and press ⌘⇧U (or Services › Speak with
  Ambient): Ambient reads it to you, with markdown, paths and code blocks turned into something worth hearing. Use a
  Mac voice, Kokoro running offline on your Mac (a one-time download), or OpenAI, ElevenLabs or your own server with
  your key. The island shows it speaking, with a stop button.
```

(use ⌃⌥⌘S instead if Task 1 chose the hotkey route), and replace "Everything stays on your Mac. No accounts, no network, no telemetry." with:

```markdown
Everything stays on your Mac. No accounts and no telemetry. Ambient goes online only when you ask it to: the one-time
offline voice download, and the text you select when you choose an online voice.
```

`SECURITY.md`: add a "Network" section stating exactly the above, that API keys are stored only in the login Keychain under `com.viveky259259.Ambient.voice`, and that the offline voice files are checked against SHA-256 hashes compiled into the app and the helper's Developer ID signature before anything is installed.

`THIRD_PARTY_NOTICES.md`: add sections for kokoro-ios (MIT, Mikko Lalma), MisakiSwift (check its LICENSE with `gh api repos/mlalma/MisakiSwift/license -q .license.spdx_id`), MLX Swift (MIT, ml-explore), MLXUtilsLibrary (check its license the same way), and Kokoro-82M (Apache-2.0, hexgrad), each with the license text, noting they're in the separately downloaded offline voice, not in Ambient itself.

`CHANGELOG.md`: under a new `## Unreleased` heading:

```markdown
### Added
- Read aloud: select text in Claude, Codex or a terminal and press ⌘⇧U to hear it, with a Mac voice, an offline
  Kokoro voice, or an online voice of your choice.
```

- [ ] **Step 7: Full check and commit**

Run: `swift test && scripts/build-app.sh --universal`
Expected: all tests pass; the universal build succeeds (proving the app still builds for Intel without the helper).

```bash
git add scripts/pin-voice-helper.sh Sources/AmbientCore/Speech/VoicePackPin.swift README.md SECURITY.md THIRD_PARTY_NOTICES.md CHANGELOG.md
git commit -m "feat(voice): pin the published offline voice pack, and document reading aloud"
```
