# Living Wallpaper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A living wallpaper (Sky, Harbor or Garden) that follows the time of day and that your agents live in. It shows the day's story, a timeline, the clock and your next event, on the desktop and on the lock screen.

**Architecture:**
- **Core logic:** the pure pieces live in `AmbientCore` and are unit-tested.
  - `DayLog`: today's story.
  - `SceneState`: everything a scene draws, as data.
  - `DayLight`: time-of-day phases.
  - `ScenePolicy`: which world is showing.
  - `WallpaperStore`: parses macOS's wallpaper store.
- **The app** draws with SwiftUI `Canvas` and places the drawing on three surfaces:
  - a desktop-level window per display;
  - a SkyLight level-400 space on the lock screen (private API, with a self-check);
  - a fallback that sets the real wallpaper only while locked and restores it from a backup.
- **Coordinator:** `LivingWallpaper` wires `AppModel`, `Preferences`, lock state and the calendar into those surfaces.

**Tech Stack:** Swift 6.4 toolchain, SwiftPM, macOS 14+, AppKit + SwiftUI (`Canvas`, `TimelineView`, `ImageRenderer`), EventKit, Swift Testing (`import Testing`), `dlopen`/`dlsym` for SkyLight.

**Spec:** `docs/superpowers/specs/2026-09-29-living-wallpaper-design.md` (read it first; the spike findings there are the evidence for every platform choice below).

## Global Constraints

- **Platform:** macOS 14 or later (`Package.swift` `.macOS(.v14)`, `LSMinimumSystemVersion` 14.0).
- **No network.** Ambient still never opens a connection: no weather, no location, no new dependencies.
- **Language modes:** `AmbientCore` is Foundation-only and builds in Swift 6 language mode; `AmbientApp` builds in Swift 5 mode.
- **Tests:** Swift Testing: `import Testing`, `@Suite struct …Tests`, `@Test func …()`, `#expect(…)`. Temporary files come from `shortTempDir()` (in `Tests/AmbientCoreTests/SocketTests.swift`).
- **Logging:** `Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")`.
- **Files Ambient writes:**
  - `~/.ambient/day.json`: 0600, atomic, debounced 1 s.
  - Backup: `~/.ambient/backups/wallpaper-Index.plist`.
  - Marker: `~/.ambient/wallpaper-swapped`.
  - Fallback images: `~/.ambient/wallpaper/scene-<uuid>.png`.
- **macOS's wallpaper store:** `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. It is written only by `WallpaperSwap`, only while locked, and only after a backup.
- **Preferences defaults:**

  | Key | Default |
  | --- | --- |
  | `wallpaperEnabled` | false |
  | `wallpaperScene` | "daily" (values "sky", "harbor", "garden", "daily") |
  | `wallpaperOnLockScreen` | true |
  | `wallpaperLockMessages` | false |
  | `wallpaperCalendar` | false |

- **Timings:** lock counts after it holds 2 s, unlock counts at once; the lock-screen self-check runs 2 s after the lock layer shows; the fallback re-renders every 30 s, and on a mood change no sooner than 8 s after the last swap.
- **SkyLight:** absolute level 400 (100 does not show on the lock screen); window added with `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [windowNumber], 7)`.
- **Privacy:**
  - `day.json` never holds free text (no summaries, prompts, tool hints or error messages).
  - The lock screen hides free text and calendar titles unless `wallpaperLockMessages` is on.
- **Copy:** plain, short sentences in the voice of the existing panes; names are "Living wallpaper", "Sky", "Harbor", "Garden", "A new one each day".

## Review Focus

1. **Ambient crashed mid-lock and the user picked a new wallpaper before relaunching.** On launch, Ambient must not overwrite their new choice. Restoring only happens while Ambient's image is still set: `WallpaperStore.references(directory:in:)` is tested in Task 3 and used in Task 7, and Task 7 has a manual step for this case.
2. **Displays change (plug or unplug a monitor, change resolution) while locked or unlocked.** A level-400 window must never be visible over the unlocked desktop, and the wallpaper windows must match the screens. `LockLayer.install()` always starts at alpha 0; the manual steps are in Tasks 5 and 6.
3. **Long titles and messages, and more than 8 sessions.** Text is clipped, "+N more" shows, and nothing runs off-screen. The tests are in Task 2 (`longTextIsClipped`, `inhabitantsMostUrgentFirstCappedAtEight`); the manual label check is in Task 5, Step 5.
4. **Clock changes:** DST days, time-zone changes, and midnight passing while the Mac sleeps. The light follows the wall clock, the day resets and the daily scene rotates on wake. The DST test is in Task 2; the time-zone, clock and wake observers are in Task 5.
5. **A future macOS changes the wallpaper store format or removes SkyLight.** Ambient never swaps, the lock status says "unavailable", and the desk still works. The unknown-format tests are in Task 3; the `SkyLight.shared == nil` path and the status are in Tasks 6 and 7.

## File Map

| File | Status | Responsibility |
| --- | --- | --- |
| `Sources/AmbientCore/DayLog.swift` | new | `DayMark`, `DayMoment`, `DayLog`, `DayLogFile`, `AmbientPaths.dayFile` |
| `Sources/AmbientCore/DayLight.swift` | new | `DayPhase`, `DayLight` (phase and blend from the wall clock) |
| `Sources/AmbientCore/ScenePolicy.swift` | new | `SceneKind`, `SceneChoice`, `ScenePolicy` |
| `Sources/AmbientCore/SceneState.swift` | new | `SceneSurface`, `CalendarEvent`, `SceneInhabitant`, `StoryItem`, `TimelineLine`, `SceneState`, `SceneLayout` |
| `Sources/AmbientCore/WallpaperStore.swift` | new | Parse and compare macOS's wallpaper store |
| `Sources/AmbientCore/Policy.swift` | modify | `RGB.mixed(with:_:)`, `GlowStyle.level(at:)` |
| `Sources/AmbientApp/AppModel.swift` | modify | Own, publish and save the `DayLog` |
| `Sources/AmbientApp/AppDelegate.swift` | modify | Pass `dayFile`; create and start `LivingWallpaper`; pass it to Settings |
| `Sources/AmbientApp/Preferences.swift` | modify | Five wallpaper keys, `sceneChoice` |
| `Sources/AmbientApp/Wallpaper/SceneRenderer.swift` | new | Renderer protocol, registry, motion, seeded random, drawing helpers |
| `Sources/AmbientApp/Wallpaper/SceneView.swift` | new | `SceneView` and `SceneTextLayer` |
| `Sources/AmbientApp/Wallpaper/SkyScene.swift` | new | Sky |
| `Sources/AmbientApp/Wallpaper/HarborScene.swift` | new | Harbor |
| `Sources/AmbientApp/Wallpaper/GardenScene.swift` | new | Garden |
| `Sources/AmbientApp/Wallpaper/SceneFeed.swift` | new | `SceneFeed` (published states), `SceneHost`, `WallpaperWindow` |
| `Sources/AmbientApp/Wallpaper/DesktopLayer.swift` | new | Desktop-level windows |
| `Sources/AmbientApp/Wallpaper/LockMonitor.swift` | new | Debounced lock state |
| `Sources/AmbientApp/Wallpaper/SkyLight.swift` | new | Private-API wrapper |
| `Sources/AmbientApp/Wallpaper/LockLayer.swift` | new | Lock-screen windows with self-check |
| `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift` | new | Fallback swap, restore, crash recovery |
| `Sources/AmbientApp/Wallpaper/CalendarSource.swift` | new | Next event via EventKit |
| `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift` | new | Coordinator |
| `Sources/AmbientApp/Settings/SettingsPane.swift` | modify | `.wallpaper` case |
| `Sources/AmbientApp/Settings/SettingsView.swift` | modify | Show `WallpaperPane`; take `LivingWallpaper` |
| `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift` | new | The pane |
| `Sources/AmbientApp/Settings/Panes/ScenePicker.swift` | new | Scene cards: Sky, Harbor, Garden, A new one each day |
| `Sources/AmbientApp/Settings/Previews/WallpaperPreview.swift` | new | Live preview with demo sessions |
| `Resources/Info.plist`, `Resources/Ambient.entitlements` | modify | Calendar usage strings and entitlement |
| `Tests/AmbientCoreTests/DayLogTests.swift` | new | |
| `Tests/AmbientCoreTests/DayLightTests.swift` | new | Also `ScenePolicy`, `GlowStyle.level`, `RGB.mixed` |
| `Tests/AmbientCoreTests/SceneStateTests.swift` | new | |
| `Tests/AmbientCoreTests/WallpaperStoreTests.swift` | new | |
| `README.md`, `CHANGELOG.md` | modify | Docs |

---

### Task 0: Branch

- [ ] **Step 1: Create the feature branch and commit the approved spec**

```bash
git checkout -b feat/living-wallpaper
git add .gitignore docs/superpowers/specs/2026-09-29-living-wallpaper-design.md docs/superpowers/plans/2026-09-29-living-wallpaper.md
git commit -m "docs: living wallpaper design and plan"
```

---

### Task 1: Day's story (`DayLog`) and its place in `AppModel`

**Files:**
- Create: `Sources/AmbientCore/DayLog.swift`
- Create: `Tests/AmbientCoreTests/DayLogTests.swift`
- Modify: `Sources/AmbientApp/AppModel.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift:10`

**Interfaces:**
- Consumes: `SessionChange` (`session`, `previous: Activity?`, `event: EventKind?`), `Session` (`turnStartedAt`, `turnEndedAt`, `lastEventAt`, `project`, `sessionId`, `activity.isBusy`), `Describe.title(_:)`, `AmbientPaths.home`.
- Produces:
  - `struct DayMark { enum Outcome { case done, failed }; let agent: AgentKind; let outcome: Outcome; let at: Date }`
  - `struct DayMoment { enum Kind { case neededYou, done, failed }; let kind; let agent; let place: String; let at: Date }`
  - `struct DayLog`:
    - `static let maxMarks = 40`, `static let maxMoments = 20`
    - `init(now: Date, calendar: Calendar = .current)`
    - `day: Date`, `finishedSeconds`, `tools`, `turnsDone`, `turnsFailed`, `neededYou`, `projects: [String]`, `longestRun`, `marks: [DayMark]` (oldest first), `moments: [DayMoment]` (newest first)
    - `mutating func rollOver(now:calendar:) -> Bool`
    - `mutating func apply(_ change: SessionChange, now: Date, calendar: Calendar = .current)`
    - `func agentTime(live: [Session], now: Date) -> TimeInterval`
  - `enum DayLogFile { static func save(_:to:) throws; static func load(from:) -> DayLog? }`
  - `AmbientPaths.dayFile`
  - `AppModel.day: DayLog` (`@Published`)

- [ ] **Step 1: Write the failing tests**

Create `Tests/AmbientCoreTests/DayLogTests.swift`:

```swift
import Foundation
import Testing
@testable import AmbientCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-09-29 00:00 UTC.
private let midnight = Date(timeIntervalSince1970: 1_790_640_000)

/// Runs events through a real store and folds each change into a log, like AppModel does.
private struct Harness {
    let store = SessionStore()
    var log: DayLog

    init(at start: Date) { log = DayLog(now: start, calendar: utc) }

    mutating func send(_ kind: EventKind, at seconds: TimeInterval, session: String = "s1", agent: AgentKind = .claude,
                       cwd: String = "/src/api") {
        let when = midnight.addingTimeInterval(seconds)
        guard let change = store.apply(AgentEvent(agent: agent, sessionId: session, cwd: cwd, kind: kind, timestamp: when))
        else { return }
        log.apply(change, now: when, calendar: utc)
    }
}

@Suite struct DayLogTests {
    @Test func countsWhatHappened() {
        var h = Harness(at: midnight.addingTimeInterval(3_600))
        h.send(.promptSubmitted, at: 3_600)
        h.send(.toolStarted(name: "Bash", detail: "npm test"), at: 3_610)
        h.send(.toolFinished(name: "Bash", failed: false), at: 3_620)
        h.send(.toolStarted(name: "Read", detail: "a.swift"), at: 3_630)
        h.send(.turnCompleted(summary: "Green"), at: 3_700)
        h.send(.promptSubmitted, at: 4_000, session: "s2", agent: .codex, cwd: "/src/web")
        h.send(.turnFailed(message: "Quota"), at: 4_060, session: "s2", agent: .codex, cwd: "/src/web")

        #expect(h.log.tools == 2)
        #expect(h.log.turnsDone == 1)
        #expect(h.log.turnsFailed == 1)
        #expect(h.log.projects == ["api", "web"])
        #expect(h.log.finishedSeconds == 160)
        #expect(h.log.longestRun == 100)
        #expect(h.log.marks.map(\.outcome) == [.done, .failed])
        #expect(h.log.marks.map(\.agent) == [.claude, .codex])
        #expect(h.log.moments.map(\.kind) == [.failed, .done])
        #expect(h.log.moments.first?.place == "web")
        #expect(h.log.moments.first?.at == midnight.addingTimeInterval(4_060))
    }

    @Test func aPromptCountsOnceWhileItWaits() {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 10)
        h.send(.needsInput(reason: "permission", message: "Bash: rm"), at: 20)
        h.send(.needsInput(reason: "permission", message: "Bash: rm"), at: 25)
        #expect(h.log.neededYou == 1)
        h.send(.toolStarted(name: "Bash", detail: "rm"), at: 30)
        h.send(.needsInput(reason: "question", message: "Which one?"), at: 40)
        #expect(h.log.neededYou == 2)
        #expect(h.log.moments.map(\.kind) == [.neededYou, .neededYou])
    }

    @Test func midnightStartsAFreshDayAndSplitsATurnThatCrossesIt() {
        var h = Harness(at: midnight.addingTimeInterval(-600))
        h.send(.promptSubmitted, at: -600)
        h.send(.toolStarted(name: "Bash", detail: nil), at: -590)
        #expect(h.log.tools == 1)
        h.send(.turnCompleted(summary: nil), at: 300)
        #expect(h.log.day == midnight)
        #expect(h.log.tools == 0)
        #expect(h.log.turnsDone == 1)
        #expect(h.log.finishedSeconds == 300)
        #expect(h.log.longestRun == 900)
    }

    @Test func rollOverOnlyPastMidnight() {
        var log = DayLog(now: midnight.addingTimeInterval(-60), calendar: utc)
        #expect(log.rollOver(now: midnight.addingTimeInterval(-1), calendar: utc) == false)
        #expect(log.rollOver(now: midnight.addingTimeInterval(1), calendar: utc) == true)
        #expect(log.day == midnight)
    }

    @Test func demoSessionsAndSweepsDontCount() {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 10, session: "demo-claude-web")
        h.send(.turnCompleted(summary: nil), at: 20, session: "demo-claude-web")
        let sweep = SessionChange(session: Session(agent: .claude, sessionId: "x", at: midnight),
                                  previous: .thinking, event: nil, removed: false)
        h.log.apply(sweep, now: midnight.addingTimeInterval(30), calendar: utc)
        #expect(h.log == DayLog(now: midnight, calendar: utc))
    }

    @Test func capsKeepTheNewestAndCountsStayExact() {
        var h = Harness(at: midnight)
        for i in 0..<50 {
            let t = TimeInterval(i * 100)
            h.send(.promptSubmitted, at: t + 1)
            h.send(.turnCompleted(summary: nil), at: t + 50)
        }
        #expect(h.log.turnsDone == 50)
        #expect(h.log.marks.count == DayLog.maxMarks)
        #expect(h.log.moments.count == DayLog.maxMoments)
        #expect(h.log.marks.last?.at == midnight.addingTimeInterval(4_950))
        #expect(h.log.moments.first?.at == midnight.addingTimeInterval(4_950))
    }

    @Test func agentTimeIncludesTurnsStillRunning() {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 0)
        h.send(.turnCompleted(summary: nil), at: 60)
        h.send(.promptSubmitted, at: 100, session: "s2")
        h.send(.toolStarted(name: "Bash", detail: nil), at: 110, session: "s2")
        #expect(h.log.agentTime(live: h.store.sessions, now: midnight.addingTimeInterval(160)) == 120)
    }

    @Test func savesWithoutFreeText() throws {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 0)
        h.send(.toolStarted(name: "Bash", detail: "SECRET-HINT"), at: 1)
        h.send(.needsInput(reason: "permission", message: "SECRET-PROMPT"), at: 2)
        h.send(.turnCompleted(summary: "SECRET-SUMMARY"), at: 3)
        h.send(.turnFailed(message: "SECRET-ERROR"), at: 4, session: "s2")
        let url = try shortTempDir().appendingPathComponent("day.json")
        try DayLogFile.save(h.log, to: url)
        #expect(DayLogFile.load(from: url) == h.log)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("SECRET"))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func missingOrCorruptFilesLoadNothing() throws {
        let url = try shortTempDir().appendingPathComponent("day.json")
        #expect(DayLogFile.load(from: url) == nil)
        try Data("{nope".utf8).write(to: url)
        #expect(DayLogFile.load(from: url) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DayLogTests`
Expected: build failure, `cannot find 'DayLog' in scope`.

- [ ] **Step 3: Implement `DayLog`**

Create `Sources/AmbientCore/DayLog.swift`:

```swift
import Foundation

/// A turn that finished today: a star, a moored boat or a flower in the day's build-up.
public struct DayMark: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case done, failed }

    public let agent: AgentKind
    public let outcome: Outcome
    public let at: Date

    public init(agent: AgentKind, outcome: Outcome, at: Date) {
        self.agent = agent
        self.outcome = outcome
        self.at = at
    }
}

/// A moment on the day's timeline. Never free text: only what happened, where and when.
public struct DayMoment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case neededYou, done, failed }

    public let kind: Kind
    public let agent: AgentKind
    /// The session's title, else its project, else the agent's name.
    public let place: String
    public let at: Date

    public init(kind: Kind, agent: AgentKind, place: String, at: Date) {
        self.kind = kind
        self.agent = agent
        self.place = place
        self.at = at
    }
}

/// Today's story, folded from session changes: totals, finished turns and recent moments.
public struct DayLog: Codable, Equatable, Sendable {
    public static let maxMarks = 40
    public static let maxMoments = 20

    /// Local midnight that starts the day this log covers.
    public private(set) var day: Date
    /// Time spent in turns that finished today; `agentTime(live:now:)` adds turns still running.
    public private(set) var finishedSeconds: TimeInterval = 0
    public private(set) var tools = 0
    public private(set) var turnsDone = 0
    public private(set) var turnsFailed = 0
    public private(set) var neededYou = 0
    public private(set) var projects: [String] = []
    public private(set) var longestRun: TimeInterval = 0
    /// Oldest first, at most `maxMarks`.
    public private(set) var marks: [DayMark] = []
    /// Newest first, at most `maxMoments`.
    public private(set) var moments: [DayMoment] = []

    public init(now: Date, calendar: Calendar = .current) {
        day = calendar.startOfDay(for: now)
    }

    /// Starts a fresh day when `now` is past this one. Returns whether it did.
    @discardableResult
    public mutating func rollOver(now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.startOfDay(for: now) > day else { return false }
        self = DayLog(now: now, calendar: calendar)
        return true
    }

    /// Counts what a change says happened. Demo sessions and sweeps (no event) don't count.
    public mutating func apply(_ change: SessionChange, now: Date, calendar: Calendar = .current) {
        rollOver(now: now, calendar: calendar)
        let s = change.session
        guard let event = change.event, !s.sessionId.hasPrefix("demo-") else { return }
        if let project = s.project, !projects.contains(project) {
            projects.append(project)
            projects.sort()
        }
        switch event {
        case .toolStarted:
            tools += 1
        case .needsInput:
            if case .waiting? = change.previous { return }
            neededYou += 1
            remember(.neededYou, s)
        case .turnCompleted:
            turnsDone += 1
            finish(s, .done)
        case .turnFailed:
            turnsFailed += 1
            finish(s, .failed)
        default:
            break
        }
    }

    /// Agent time today, including turns still running. Parallel sessions add up.
    public func agentTime(live sessions: [Session], now: Date) -> TimeInterval {
        sessions.reduce(finishedSeconds) { total, s in
            guard !s.sessionId.hasPrefix("demo-"), s.activity.isBusy,
                  let start = s.turnStartedAt, s.turnEndedAt == nil else { return total }
            return total + max(0, now.timeIntervalSince(max(start, day)))
        }
    }

    private mutating func finish(_ s: Session, _ outcome: DayMark.Outcome) {
        if let start = s.turnStartedAt, let end = s.turnEndedAt, end >= start {
            finishedSeconds += max(0, end.timeIntervalSince(max(start, day)))
            longestRun = max(longestRun, end.timeIntervalSince(start))
        }
        marks.append(DayMark(agent: s.agent, outcome: outcome, at: s.lastEventAt))
        if marks.count > Self.maxMarks { marks.removeFirst(marks.count - Self.maxMarks) }
        remember(outcome == .done ? .done : .failed, s)
    }

    private mutating func remember(_ kind: DayMoment.Kind, _ s: Session) {
        moments.insert(DayMoment(kind: kind, agent: s.agent, place: Describe.title(s), at: s.lastEventAt), at: 0)
        if moments.count > Self.maxMoments { moments.removeLast(moments.count - Self.maxMoments) }
    }
}

/// Today's story, saved across restarts.
public enum DayLogFile {
    private struct Envelope: Codable {
        var version = 1
        var log: DayLog
    }

    public static func save(_ log: DayLog, to url: URL) throws {
        let data = try JSONEncoder().encode(Envelope(log: log))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// What was saved, or nil if the file is missing, corrupt or from another version.
    public static func load(from url: URL) -> DayLog? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return nil }
        return envelope.log
    }
}

extension AmbientPaths {
    public var dayFile: URL { home.appendingPathComponent("day.json") }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DayLogTests`
Expected: all 9 tests pass.

- [ ] **Step 5: Give `AppModel` the day**

In `Sources/AmbientApp/AppModel.swift`:

Add below `@Published private(set) var mood: Mood = .idle`:

```swift
    /// Today's story, for the living wallpaper.
    @Published private(set) var day = DayLog(now: Date())
```

Add below `private let stateURL: URL?`:

```swift
    private let dayURL: URL?
    private var daySaveWork: DispatchWorkItem?
```

Replace the initializer:

```swift
    init(prefs: Preferences, stateURL: URL?, dayURL: URL? = nil, titles: SessionTitles? = nil) {
        self.prefs = prefs
        self.stateURL = stateURL
        self.dayURL = dayURL
        self.titles = titles
    }
```

In `start()`, add as the first lines:

```swift
        if let dayURL, let saved = DayLogFile.load(from: dayURL) { day = saved }
        rollOverDay()
```

In `apply(_:)`, after `transitions.send(t)`:

```swift
        record(t)
```

In `sweep()`, after `refreshTitles()`:

```swift
        rollOverDay()
```

In `saveNow()`, as the first lines:

```swift
        daySaveWork?.cancel()
        if let dayURL { try? DayLogFile.save(day, to: dayURL) }
```

Add these methods before `publish(save:)`:

```swift
    /// Counts an applied event in today's story.
    private func record(_ t: SessionChange) {
        var next = day
        next.apply(t, now: Date())
        guard next != day else { return }
        day = next
        scheduleDaySave()
    }

    /// Starts a fresh day after midnight. Copies first: mutating a @Published value in place publishes even when nothing changes.
    private func rollOverDay() {
        var next = day
        guard next.rollOver(now: Date()) else { return }
        day = next
        scheduleDaySave()
    }

    private func scheduleDaySave() {
        guard let dayURL else { return }
        daySaveWork?.cancel()
        let log = day
        let work = DispatchWorkItem { try? DayLogFile.save(log, to: dayURL) }
        daySaveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }
```

In `Sources/AmbientApp/AppDelegate.swift`, replace line 10:

```swift
    private lazy var model = AppModel(prefs: prefs, stateURL: paths.stateFile, dayURL: paths.dayFile,
                                      titles: SessionTitles(userHome: paths.userHome))
```

- [ ] **Step 6: Build and run all tests**

Run: `swift build && swift test`
Expected: build succeeds; every suite passes.

- [ ] **Step 7: Commit**

```bash
git add Sources/AmbientCore/DayLog.swift Tests/AmbientCoreTests/DayLogTests.swift Sources/AmbientApp/AppModel.swift Sources/AmbientApp/AppDelegate.swift
git commit -m "feat(core): DayLog, today's story for the living wallpaper"
```

---

### Task 2: Scene data: light, choice, state

**Files:**
- Create: `Sources/AmbientCore/DayLight.swift`
- Create: `Sources/AmbientCore/ScenePolicy.swift`
- Create: `Sources/AmbientCore/SceneState.swift`
- Modify: `Sources/AmbientCore/Policy.swift` (append two extensions)
- Create: `Tests/AmbientCoreTests/DayLightTests.swift`
- Create: `Tests/AmbientCoreTests/SceneStateTests.swift`

**Interfaces:**
- Consumes: `DayLog` (Task 1), `Session`, `Describe.shortActivity/clock/title/place/duration`, `Trim.truncate/clean`, `GlowStyle`, `RGB`.
- Produces:
  - `RGB.mixed(with: RGB, _ t: Double) -> RGB`
  - `GlowStyle.level(at: TimeInterval) -> Double`
  - `enum DayPhase { night, dawn, day, dusk }`
  - `struct DayLight`:
    - `from`, `to`, `blend`, `dominant`, `darkInk`
    - `color(_ table: (DayPhase) -> RGB) -> RGB`, `amount(_ table: (DayPhase) -> Double) -> Double`
    - `static func at(_: Date, calendar: Calendar = .current) -> DayLight`
  - `enum SceneKind: String, CaseIterable { sky, harbor, garden }` with `displayName`
  - `enum SceneChoice: RawRepresentable { fixed(SceneKind), daily }` (rawValue "sky" | "harbor" | "garden" | "daily")
  - `ScenePolicy.kind(for: SceneChoice, on: Date, calendar:) -> SceneKind`
  - `enum SceneSurface { desk, lock }`
  - `struct CalendarEvent { title: String; start: Date }`
  - `struct SceneInhabitant: Identifiable { id, agent, mood, busyness: Double, slot: Int, headline, place, detail: String? }`
  - `struct StoryItem { value, label }`, `struct TimelineLine { time, text }`
  - `struct SceneState`:
    - `kind`, `surface`, `light`, `now`, `inhabitants`, `overflow`, `marks: [DayMark]`, `clock: String?`, `date: String?`, `nextEvent: String?`, `story: [StoryItem]`, `timeline: [TimelineLine]`
    - `static let maxInhabitants = 8`, `static let timelineLength = 4`
    - `static func make(sessions:day:now:kind:surface:lockMessages:nextEvent:keeping:calendar:locale:) -> SceneState`
    - `func scenery() -> SceneState`
  - `enum SceneLayout { static let slotCount = 12; static func slots(for ids: [String], keeping: [String: Int] = [:]) -> [String: Int] }`

- [ ] **Step 1: Write the failing tests for light, choice, glow and color**

Create `Tests/AmbientCoreTests/DayLightTests.swift`:

```swift
import Foundation
import Testing
@testable import AmbientCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-09-29 at a UTC wall-clock time.
private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    Date(timeIntervalSince1970: 1_790_640_000 + TimeInterval(hour * 3_600 + minute * 60 + second))
}

@Suite struct DayLightTests {
    @Test func steadyPhases() {
        #expect(DayLight.at(at(4, 59), calendar: utc) == DayLight(from: .night, to: .night, blend: 0))
        #expect(DayLight.at(at(6, 15), calendar: utc) == DayLight(from: .dawn, to: .dawn, blend: 0))
        #expect(DayLight.at(at(12, 0), calendar: utc) == DayLight(from: .day, to: .day, blend: 0))
        #expect(DayLight.at(at(19, 0), calendar: utc) == DayLight(from: .dusk, to: .dusk, blend: 0))
        #expect(DayLight.at(at(22, 0), calendar: utc) == DayLight(from: .night, to: .night, blend: 0))
        #expect(DayLight.at(at(23, 59, 59), calendar: utc).dominant == .night)
    }

    @Test func blendsAcrossTransitions() {
        #expect(DayLight.at(at(5, 30), calendar: utc) == DayLight(from: .night, to: .dawn, blend: 0.5))
        #expect(DayLight.at(at(7, 0), calendar: utc) == DayLight(from: .dawn, to: .day, blend: 0.5))
        #expect(DayLight.at(at(18, 0), calendar: utc) == DayLight(from: .day, to: .dusk, blend: 0.5))
        #expect(DayLight.at(at(20, 30), calendar: utc) == DayLight(from: .dusk, to: .night, blend: 0.5))
    }

    @Test func darkInkOnlyByDay() {
        #expect(DayLight.at(at(12, 0), calendar: utc).darkInk)
        #expect(DayLight.at(at(17, 59), calendar: utc).darkInk)
        #expect(!DayLight.at(at(18, 1), calendar: utc).darkInk)
        #expect(!DayLight.at(at(2, 0), calendar: utc).darkInk)
    }

    @Test func followsTheWallClockOnDaylightSavingDays() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-03-08 is 23 hours long in New York. Noon is still day.
        let noon = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        #expect(DayLight.at(noon, calendar: ny) == DayLight(from: .day, to: .day, blend: 0))
    }

    @Test func mixesColorsAndAmounts() {
        let light = DayLight(from: .night, to: .dawn, blend: 0.25)
        let mixed = light.color { $0 == .night ? RGB(r: 0, g: 0, b: 0) : RGB(r: 1, g: 1, b: 1) }
        #expect(mixed == RGB(r: 0.25, g: 0.25, b: 0.25))
        #expect(light.amount { $0 == .night ? 1 : 0 } == 0.75)
    }
}

@Suite struct ScenePolicyTests {
    @Test func aPickedSceneStays() {
        #expect(ScenePolicy.kind(for: .fixed(.harbor), on: at(3, 0), calendar: utc) == .harbor)
    }

    @Test func dailyChangesAtMidnightAndCyclesThroughAll() {
        let today = ScenePolicy.kind(for: .daily, on: at(0, 1), calendar: utc)
        #expect(ScenePolicy.kind(for: .daily, on: at(23, 59), calendar: utc) == today)
        let tomorrow = ScenePolicy.kind(for: .daily, on: at(0, 1).addingTimeInterval(86_400), calendar: utc)
        let after = ScenePolicy.kind(for: .daily, on: at(0, 1).addingTimeInterval(2 * 86_400), calendar: utc)
        #expect(Set([today, tomorrow, after]) == Set(SceneKind.allCases))
    }

    @Test func choicesRoundTripThroughTheirRawValues() {
        for raw in ["sky", "harbor", "garden", "daily"] { #expect(SceneChoice(rawValue: raw)?.rawValue == raw) }
        #expect(SceneChoice(rawValue: "ocean") == nil)
    }
}

@Suite struct GlowLevelTests {
    @Test func steadyGlowsHoldHigh() {
        let done = GlowStyle.for(mood: .done, agent: .claude)!
        #expect(done.level(at: 0) == done.high)
        #expect(done.level(at: 12.3) == done.high)
    }

    @Test func breathingGlowsGoFromLowToHighAndBack() {
        let working = GlowStyle.for(mood: .working, agent: .claude)!
        #expect(abs(working.level(at: 0) - working.low) < 1e-9)
        #expect(abs(working.level(at: 1.6) - working.high) < 1e-9)
        #expect(abs(working.level(at: 3.2) - working.low) < 1e-9)
    }

    @Test func rgbMixClamps() {
        let a = RGB(r: 0, g: 0.5, b: 1), b = RGB(r: 1, g: 0.5, b: 0)
        #expect(a.mixed(with: b, 0.5) == RGB(r: 0.5, g: 0.5, b: 0.5))
        #expect(a.mixed(with: b, 2) == b)
        #expect(a.mixed(with: b, -1) == a)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "DayLightTests|ScenePolicyTests|GlowLevelTests"`
Expected: build failure, `cannot find 'DayLight' in scope`.

- [ ] **Step 3: Implement color mixing, glow level, light and choice**

Append to `Sources/AmbientCore/Policy.swift`:

```swift
extension RGB {
    /// A straight mix toward `other`; `t` is clamped to 0...1.
    public func mixed(with other: RGB, _ t: Double) -> RGB {
        let t = min(1, max(0, t))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

extension GlowStyle {
    /// Brightness at a moment: a smooth breath from `low` to `high` and back, or `high` when steady.
    public func level(at time: TimeInterval) -> Double {
        guard let period, period > 0 else { return high }
        let phase = time.truncatingRemainder(dividingBy: period) / period
        return low + (high - low) * (0.5 - 0.5 * cos(phase * 2 * .pi))
    }
}
```

Create `Sources/AmbientCore/DayLight.swift`:

```swift
import Foundation

/// The four looks a scene takes through the day.
public enum DayPhase: String, CaseIterable, Sendable {
    case night, dawn, day, dusk
}

/// Where the day is: the phase the scene is in, the one it's turning into, and how far along.
public struct DayLight: Equatable, Sendable {
    public let from: DayPhase
    public let to: DayPhase
    /// 0 is all `from`, 1 is all `to`.
    public let blend: Double

    public init(from: DayPhase, to: DayPhase, blend: Double) {
        self.from = from
        self.to = to
        self.blend = blend
    }

    public var dominant: DayPhase { blend < 0.5 ? from : to }

    /// Dark text by day; light text at night, dawn and dusk.
    public var darkInk: Bool { dominant == .day }

    public func color(_ table: (DayPhase) -> RGB) -> RGB { table(from).mixed(with: table(to), blend) }

    public func amount(_ table: (DayPhase) -> Double) -> Double {
        table(from) + (table(to) - table(from)) * blend
    }

    /// Minutes after local midnight where the look changes. Between two keys of different phases the
    /// scene blends: night → dawn 05:00–06:00, dawn → day 06:30–07:30, day → dusk 17:30–18:30,
    /// dusk → night 20:00–21:00.
    static let keys: [(minute: Double, phase: DayPhase)] = [
        (0, .night), (300, .night), (360, .dawn), (390, .dawn), (450, .day),
        (1_050, .day), (1_110, .dusk), (1_200, .dusk), (1_260, .night), (1_440, .night),
    ]

    /// The light at a wall-clock time. Reads the hour and minute, so daylight-saving days keep to schedule.
    public static func at(_ date: Date, calendar: Calendar = .current) -> DayLight {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
        for (a, b) in zip(keys, keys.dropFirst()) where minute >= a.minute && minute < b.minute {
            guard a.phase != b.phase else { return DayLight(from: a.phase, to: a.phase, blend: 0) }
            return DayLight(from: a.phase, to: b.phase, blend: (minute - a.minute) / (b.minute - a.minute))
        }
        return DayLight(from: .night, to: .night, blend: 0)
    }
}
```

Create `Sources/AmbientCore/ScenePolicy.swift`:

```swift
import Foundation

/// The worlds the living wallpaper can show.
public enum SceneKind: String, CaseIterable, Codable, Sendable {
    case sky, harbor, garden

    public var displayName: String {
        switch self {
        case .sky: "Sky"
        case .harbor: "Harbor"
        case .garden: "Garden"
        }
    }
}

/// What the user picked in Settings: one world, or a new one each day.
public enum SceneChoice: Equatable, Sendable, RawRepresentable {
    case fixed(SceneKind)
    case daily

    public init?(rawValue: String) {
        if rawValue == "daily" {
            self = .daily
        } else if let kind = SceneKind(rawValue: rawValue) {
            self = .fixed(kind)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .daily: "daily"
        case let .fixed(kind): kind.rawValue
        }
    }
}

public enum ScenePolicy {
    /// The world to show: the picked one, or one per day in a fixed order that changes at local midnight.
    public static func kind(for choice: SceneChoice, on date: Date, calendar: Calendar = .current) -> SceneKind {
        switch choice {
        case let .fixed(kind):
            return kind
        case .daily:
            let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
            return SceneKind.allCases[day % SceneKind.allCases.count]
        }
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter "DayLightTests|ScenePolicyTests|GlowLevelTests"`
Expected: all pass.

- [ ] **Step 5: Write the failing tests for `SceneState`**

Create `Tests/AmbientCoreTests/SceneStateTests.swift`:

```swift
import Foundation
import Testing
@testable import AmbientCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let gb = Locale(identifier: "en_GB")
/// 2026-09-29 18:42 UTC.
private let evening = Date(timeIntervalSince1970: 1_790_707_320)
private let review = CalendarEvent(title: "Design review", start: evening.addingTimeInterval(48 * 60))

private func session(_ id: String, _ activity: Activity, agent: AgentKind = .claude, cwd: String = "/src/api",
                     title: String? = nil, tools: Int = 0, lastEvent: TimeInterval = 0) -> Session {
    var s = Session(agent: agent, sessionId: id, at: evening)
    s.cwd = cwd
    s.title = title
    s.activity = activity
    s.toolCount = tools
    s.turnStartedAt = evening.addingTimeInterval(-600)
    s.activitySince = evening.addingTimeInterval(-120)
    s.lastEventAt = evening.addingTimeInterval(lastEvent)
    return s
}

private func make(_ sessions: [Session], surface: SceneSurface = .desk, lockMessages: Bool = false,
                  event: CalendarEvent? = review, day: DayLog = DayLog(now: evening, calendar: utc),
                  keeping: [String: Int] = [:]) -> SceneState {
    SceneState.make(sessions: sessions, day: day, now: evening, kind: .sky, surface: surface,
                    lockMessages: lockMessages, nextEvent: event, keeping: keeping, calendar: utc, locale: gb)
}

@Suite struct SceneStateTests {
    @Test func theDeskShowsClockDateAndEvent() {
        let state = make([])
        #expect(state.clock == "18:42")
        #expect(state.date?.contains("29") == true)
        #expect(state.date?.contains("September") == true)
        #expect(state.nextEvent == "Design review at 19:30")
        #expect(state.light.dominant == .dusk)
    }

    @Test func theLockScreenHidesItsClockAndFreeText() {
        let working = session("a", .tool(name: "Bash", detail: "npm test"), tools: 3)
        let locked = make([working], surface: .lock)
        #expect(locked.clock == nil)
        #expect(locked.date == nil)
        #expect(locked.inhabitants.first?.detail == nil)
        #expect(locked.nextEvent == "Next event at 19:30")

        let allowed = make([working], surface: .lock, lockMessages: true)
        #expect(allowed.inhabitants.first?.detail == "npm test")
        #expect(allowed.nextEvent == "Design review at 19:30")
    }

    @Test func inhabitantsMostUrgentFirstCappedAtEight() {
        var sessions = (0..<9).map { session("w\($0)", .thinking, lastEvent: TimeInterval(-$0)) }
        sessions.append(session("x", .waiting(reason: "permission", message: "Bash: rm")))
        let state = make(sessions)
        #expect(state.inhabitants.count == SceneState.maxInhabitants)
        #expect(state.overflow == 2)
        #expect(state.inhabitants.first?.id == "claude:x")
        #expect(state.inhabitants.first?.mood == .waiting)
        #expect(Set(state.inhabitants.map(\.slot)).count == SceneState.maxInhabitants)
    }

    @Test func labelsReadNaturally() {
        let s = session("a", .waiting(reason: "permission", message: "Bash: swift test"),
                        cwd: "/x/ambient-notification", title: "Wallpaper that follows agents")
        let inhabitant = make([s]).inhabitants[0]
        #expect(inhabitant.headline == "Claude · Needs you · 2m")
        #expect(inhabitant.place == "Wallpaper that follows agents · ambient-notification")
        #expect(inhabitant.detail == "Bash: swift test")
    }

    @Test func longTextIsClipped() {
        let s = session("a", .done(summary: String(repeating: "word ", count: 40)),
                        title: String(repeating: "T", count: 100))
        let inhabitant = make([s]).inhabitants[0]
        #expect(inhabitant.place.count <= 48 + 3 + 32)
        #expect(inhabitant.place.hasPrefix(String(repeating: "T", count: 47) + "…"))
        #expect((inhabitant.detail?.count ?? 0) <= 80)
        #expect(inhabitant.detail?.hasSuffix("…") == true)
    }

    @Test func busynessGrowsWithToolsOnALogScale() {
        #expect(SceneState.busyness(tools: 0) == 0)
        #expect(SceneState.busyness(tools: 64) == 1)
        #expect(SceneState.busyness(tools: 1_000) == 1)
        let three = SceneState.busyness(tools: 3)
        #expect(three > 0.3 && three < 0.4)
    }

    @Test func slotsStayPutWhenSessionsArrive() {
        let first = SceneLayout.slots(for: ["claude:a", "claude:b"])
        let later = SceneLayout.slots(for: ["claude:a", "claude:b", "codex:c", "gemini:d"], keeping: first)
        #expect(later["claude:a"] == first["claude:a"])
        #expect(later["claude:b"] == first["claude:b"])
        #expect(Set(later.values).count == 4)
        #expect(later.values.allSatisfy { (0..<SceneLayout.slotCount).contains($0) })
        // Stable across launches: no per-process hash seed.
        #expect(SceneLayout.slots(for: ["claude:a"]) == SceneLayout.slots(for: ["claude:a"]))
    }

    @Test func theStoryReadsTheDay() {
        let store = SessionStore()
        var day = DayLog(now: evening, calendar: utc)
        let steps: [(EventKind, TimeInterval)] = [(.promptSubmitted, -100), (.toolStarted(name: "Bash", detail: nil), -90),
                                                  (.toolStarted(name: "Read", detail: nil), -80), (.turnCompleted(summary: nil), -10)]
        for (kind, t) in steps {
            let change = store.apply(AgentEvent(agent: .claude, sessionId: "s", cwd: "/src/api", kind: kind,
                                                timestamp: evening.addingTimeInterval(t)))!
            day.apply(change, now: evening.addingTimeInterval(t), calendar: utc)
        }
        let state = make(store.sessions, day: day)
        #expect(state.story == [
            StoryItem(value: "1m", label: "of agent time"),
            StoryItem(value: "2", label: "tools"),
            StoryItem(value: "1", label: "turn done"),
            StoryItem(value: "1", label: "project"),
            StoryItem(value: "1m", label: "longest run"),
        ])
        #expect(state.timeline == [TimelineLine(time: "18:41", text: "Claude finished · api")])
        #expect(state.marks.count == 1)
        #expect(make([]).story.isEmpty)
    }

    @Test func theTimelineShowsTheLatestFour() {
        let store = SessionStore()
        var day = DayLog(now: evening, calendar: utc)
        for i in 0..<6 {
            let t = TimeInterval(-600 + i * 60)
            let kinds: [EventKind] = [.promptSubmitted, .turnCompleted(summary: nil)]
            for kind in kinds {
                let change = store.apply(AgentEvent(agent: .claude, sessionId: "s\(i)", cwd: "/src/p\(i)", kind: kind,
                                                    timestamp: evening.addingTimeInterval(t)))!
                day.apply(change, now: evening.addingTimeInterval(t), calendar: utc)
            }
        }
        let timeline = make([], day: day).timeline
        #expect(timeline.count == SceneState.timelineLength)
        #expect(timeline.first?.text == "Claude finished · p5")
    }

    @Test func sceneryDropsInhabitantsAndText() {
        let full = make([session("a", .thinking)])
        let scenery = full.scenery()
        #expect(scenery.kind == full.kind)
        #expect(scenery.light == full.light)
        #expect(scenery.inhabitants.isEmpty)
        #expect(scenery.clock == nil && scenery.nextEvent == nil)
        #expect(scenery.story.isEmpty && scenery.timeline.isEmpty && scenery.marks.isEmpty)
    }
}
```

- [ ] **Step 6: Run them to verify they fail**

Run: `swift test --filter SceneStateTests`
Expected: build failure, `cannot find 'SceneState' in scope`.

- [ ] **Step 7: Implement `SceneState` and `SceneLayout`**

Create `Sources/AmbientCore/SceneState.swift`:

```swift
import Foundation

/// Where a scene is drawn. The lock screen has its own clock and is readable by anyone nearby.
public enum SceneSurface: Sendable {
    case desk, lock
}

/// The next event today, from the user's calendar.
public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let start: Date

    public init(title: String, start: Date) {
        self.title = title
        self.start = start
    }
}

/// One session, as a scene draws it.
public struct SceneInhabitant: Identifiable, Equatable, Sendable {
    public let id: String
    public let agent: AgentKind
    /// Drives the glow. Follows acknowledgement, like the island and the Dock glow.
    public let mood: Mood
    /// 0...1: how much the current turn has done, from its tool count.
    public let busyness: Double
    /// A stable spot, `0..<SceneLayout.slotCount`.
    public let slot: Int
    /// "Claude · Needs you · 2m"
    public let headline: String
    /// "Wallpaper that follows agents · ambient-notification"
    public let place: String
    /// Free text: the tool hint, prompt, summary or error. Nil on the lock screen unless allowed.
    public let detail: String?
}

/// "612 tools": a number and what it counts.
public struct StoryItem: Equatable, Sendable {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// "10:42  Gemini finished · docs"
public struct TimelineLine: Equatable, Sendable {
    public let time: String
    public let text: String

    public init(time: String, text: String) {
        self.time = time
        self.text = text
    }
}

/// Everything a scene draws, as data. Built once per change and once a minute.
public struct SceneState: Equatable, Sendable {
    public static let maxInhabitants = 8
    public static let timelineLength = 4

    public let kind: SceneKind
    public let surface: SceneSurface
    public let light: DayLight
    public let now: Date
    /// Most urgent first.
    public let inhabitants: [SceneInhabitant]
    /// Sessions beyond `maxInhabitants`.
    public let overflow: Int
    public let marks: [DayMark]
    /// Nil on the lock screen, which draws its own clock and date.
    public let clock: String?
    public let date: String?
    public let nextEvent: String?
    public let story: [StoryItem]
    public let timeline: [TimelineLine]

    public static func make(sessions: [Session], day: DayLog, now: Date, kind: SceneKind, surface: SceneSurface,
                            lockMessages: Bool = false, nextEvent: CalendarEvent? = nil,
                            keeping previousSlots: [String: Int] = [:],
                            calendar: Calendar = .current, locale: Locale = .current) -> SceneState {
        let freeText = surface == .desk || lockMessages
        let ordered = sessions.sorted {
            if $0.mood != $1.mood { return $0.mood > $1.mood }
            if $0.lastEventAt != $1.lastEventAt { return $0.lastEventAt > $1.lastEventAt }
            return $0.id < $1.id
        }
        let shown = Array(ordered.prefix(maxInhabitants))
        let slots = SceneLayout.slots(for: shown.map(\.id), keeping: previousSlots)
        let time = formatter("jmm", calendar: calendar, locale: locale)
        return SceneState(
            kind: kind,
            surface: surface,
            light: DayLight.at(now, calendar: calendar),
            now: now,
            inhabitants: shown.map { inhabitant($0, slot: slots[$0.id] ?? 0, now: now, freeText: freeText) },
            overflow: ordered.count - shown.count,
            marks: day.marks,
            clock: surface == .desk ? time.string(from: now) : nil,
            date: surface == .desk ? formatter("EEEEdMMMM", calendar: calendar, locale: locale).string(from: now) : nil,
            nextEvent: nextEvent.map { event in
                let start = time.string(from: event.start)
                return freeText ? "\(Trim.truncate(event.title, max: 40)) at \(start)" : "Next event at \(start)"
            },
            story: story(day, sessions: sessions, now: now),
            timeline: day.moments.prefix(timelineLength).map { line($0, time: time) })
    }

    /// The world without inhabitants or text, for displays other than the main one and for thumbnails.
    public func scenery() -> SceneState {
        SceneState(kind: kind, surface: surface, light: light, now: now, inhabitants: [], overflow: 0, marks: [],
                   clock: nil, date: nil, nextEvent: nil, story: [], timeline: [])
    }

    /// 0 with no tools, 1 at 64 and beyond, on a log scale so the first few tools show.
    static func busyness(tools: Int) -> Double {
        min(1, log2(1 + Double(max(0, tools))) / log2(65))
    }

    private static func inhabitant(_ s: Session, slot: Int, now: Date, freeText: Bool) -> SceneInhabitant {
        var headline = "\(s.agent.displayName) · \(Describe.shortActivity(s.activity))"
        if let clock = Describe.clock(s, now: now, compact: true) { headline += " · \(clock)" }
        var place = Trim.truncate(Describe.title(s), max: 48)
        if let project = Describe.place(s) { place += " · \(Trim.truncate(project, max: 32))" }
        return SceneInhabitant(id: s.id, agent: s.agent, mood: s.mood, busyness: busyness(tools: s.toolCount),
                               slot: slot, headline: headline, place: place,
                               detail: freeText ? detail(s.activity) : nil)
    }

    private static func detail(_ activity: Activity) -> String? {
        switch activity {
        case let .tool(_, detail): Trim.clean(detail, max: 80)
        case let .waiting(_, message): Trim.clean(message, max: 80)
        case let .done(summary): Trim.clean(summary, max: 80)
        case let .error(message): Trim.clean(message, max: 80)
        case .idle, .thinking, .compacting: nil
        }
    }

    private static func story(_ day: DayLog, sessions: [Session], now: Date) -> [StoryItem] {
        func count(_ n: Int, _ one: String, _ many: String) -> StoryItem { StoryItem(value: "\(n)", label: n == 1 ? one : many) }
        var items: [StoryItem] = []
        let agentTime = day.agentTime(live: sessions, now: now)
        if agentTime >= 60 { items.append(StoryItem(value: Describe.duration(agentTime), label: "of agent time")) }
        if day.tools > 0 { items.append(count(day.tools, "tool", "tools")) }
        if day.turnsDone > 0 { items.append(count(day.turnsDone, "turn done", "turns done")) }
        if day.turnsFailed > 0 { items.append(StoryItem(value: "\(day.turnsFailed)", label: "failed")) }
        if day.neededYou > 0 { items.append(count(day.neededYou, "call for you", "calls for you")) }
        if !day.projects.isEmpty { items.append(count(day.projects.count, "project", "projects")) }
        if day.longestRun >= 60 { items.append(StoryItem(value: Describe.duration(day.longestRun), label: "longest run")) }
        return items
    }

    private static func line(_ moment: DayMoment, time: DateFormatter) -> TimelineLine {
        let verb = switch moment.kind {
        case .neededYou: "needed you"
        case .done: "finished"
        case .failed: "failed"
        }
        return TimelineLine(time: time.string(from: moment.at),
                            text: "\(moment.agent.displayName) \(verb) · \(Trim.truncate(moment.place, max: 40))")
    }

    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}

/// Stable spots for inhabitants: a session keeps its spot for as long as it lives.
public enum SceneLayout {
    public static let slotCount = 12

    /// Spots by session id. Sessions that already had one keep it. A new session takes the spot its id hashes to
    /// (FNV-1a: the same on every launch, unlike `Hasher`), or the next free one.
    public static func slots(for ids: [String], keeping previous: [String: Int] = [:]) -> [String: Int] {
        var result: [String: Int] = [:]
        var taken = Set<Int>()
        for id in ids {
            if let slot = previous[id], (0..<slotCount).contains(slot), !taken.contains(slot) {
                result[id] = slot
                taken.insert(slot)
            }
        }
        for id in ids.sorted() where result[id] == nil {
            var slot = Int(fnv1a(id) % UInt64(slotCount))
            while taken.contains(slot) { slot = (slot + 1) % slotCount }
            result[id] = slot
            taken.insert(slot)
        }
        return result
    }

    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}
```

Note: `slots` assumes `ids.count <= slotCount`; `make` passes at most `maxInhabitants` (8) ids.

- [ ] **Step 8: Run the scene tests, then everything**

Run: `swift test --filter SceneStateTests && swift test`
Expected: all pass. If `theDeskShowsClockDateAndEvent` fails on the date string only, print `state.date` and check that the ICU output for `en_GB` contains both "29" and "September". The assertion is deliberately loose about punctuation.

- [ ] **Step 9: Commit**

```bash
git add Sources/AmbientCore/DayLight.swift Sources/AmbientCore/ScenePolicy.swift Sources/AmbientCore/SceneState.swift Sources/AmbientCore/Policy.swift Tests/AmbientCoreTests/DayLightTests.swift Tests/AmbientCoreTests/SceneStateTests.swift
git commit -m "feat(core): scene state, day light and scene choice for the living wallpaper"
```

---

### Task 3: Reading macOS's wallpaper store (`WallpaperStore`)

**Files:**
- Create: `Sources/AmbientCore/WallpaperStore.swift`
- Create: `Tests/AmbientCoreTests/WallpaperStoreTests.swift`

**Interfaces:**
- Produces:
  - `WallpaperStore.url(userHome: URL) -> URL`
  - `WallpaperStore.desktopProvider(of: Data) -> String?`
  - `WallpaperStore.isKnownFormat(_: Data) -> Bool`
  - `WallpaperStore.matches(_: Data, _: Data) -> Bool` (ignores `LastSet`/`LastUse`, compares nested plists by content)
  - `WallpaperStore.references(directory: URL, in: Data) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AmbientCoreTests/WallpaperStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import AmbientCore

private func plist(_ value: Any, _ format: PropertyListSerialization.PropertyListFormat = .binary) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
}

private func choice(_ provider: String, _ configuration: [String: Any]?,
                    format: PropertyListSerialization.PropertyListFormat = .binary) -> [String: Any] {
    ["Provider": provider, "Files": [Any](), "Configuration": configuration.map { plist($0, format) } ?? Data()]
}

private func entry(_ c: [String: Any], _ lastUse: Date) -> [String: Any] {
    ["Content": ["Choices": [c], "Shuffle": "$null", "EncodedOptionValues": "$null"], "LastSet": lastUse, "LastUse": lastUse]
}

/// A store shaped like macOS 27's: every Space and display, per display, per Space, and the system default.
private func store(desktop: [String: Any], idle: [String: Any], lastUse: Date = Date(timeIntervalSince1970: 1),
                   spaces: [String: Any] = [:]) -> Data {
    plist([
        "AllSpacesAndDisplays": ["Desktop": entry(desktop, lastUse), "Idle": entry(idle, lastUse), "Type": "individual"],
        "Displays": [String: Any](),
        "Spaces": spaces,
        "SystemDefault": ["Desktop": entry(desktop, lastUse)],
    ])
}

private let black = choice("com.apple.wallpaper.choice.color", ["type": "systemColor", "systemColor": ["black": [String: Any]()]])
private let aerial = choice("com.apple.wallpaper.choice.sequoia", nil)

private func image(_ path: String) -> [String: Any] {
    choice("com.apple.wallpaper.choice.image", ["type": "imageFile", "url": ["relative": URL(fileURLWithPath: path).absoluteString]])
}

@Suite struct WallpaperStoreTests {
    @Test func readsTheDesktopChoice() {
        let data = store(desktop: black, idle: aerial)
        #expect(WallpaperStore.desktopProvider(of: data) == "com.apple.wallpaper.choice.color")
        #expect(WallpaperStore.isKnownFormat(data))
    }

    @Test func refusesFormatsItDoesntKnow() {
        #expect(!WallpaperStore.isKnownFormat(Data("nope".utf8)))
        #expect(!WallpaperStore.isKnownFormat(plist(["Something": "else"])))
        #expect(!WallpaperStore.isKnownFormat(plist(["AllSpacesAndDisplays": ["Desktop": ["Content": ["Choices": [Any]()]]]])))
    }

    @Test func matchingIgnoresWhenThingsWereLastUsed() {
        #expect(WallpaperStore.matches(store(desktop: black, idle: aerial, lastUse: Date(timeIntervalSince1970: 1)),
                                       store(desktop: black, idle: aerial, lastUse: Date(timeIntervalSince1970: 999))))
    }

    @Test func differentChoicesDontMatch() {
        let original = store(desktop: black, idle: aerial)
        #expect(!WallpaperStore.matches(original, store(desktop: image("/tmp/a.png"), idle: aerial)))
        #expect(!WallpaperStore.matches(original, store(desktop: black, idle: aerial,
                                                        spaces: ["S1": ["Default": entry(image("/tmp/a.png"), Date())]])))
        #expect(!WallpaperStore.matches(original, Data("nope".utf8)))
    }

    @Test func nestedConfigurationsCompareByContent() {
        let xmlBlack = choice("com.apple.wallpaper.choice.color",
                              ["type": "systemColor", "systemColor": ["black": [String: Any]()]], format: .xml)
        #expect(WallpaperStore.matches(store(desktop: black, idle: aerial), store(desktop: xmlBlack, idle: aerial)))
    }

    @Test func findsAmbientsImagesWhereverTheyAreSet() {
        let dir = URL(fileURLWithPath: "/Users/Jane Doe/.ambient/wallpaper", isDirectory: true)
        let swapped = store(desktop: black, idle: aerial,
                            spaces: ["S1": ["Default": entry(image("/Users/Jane Doe/.ambient/wallpaper/scene-1.png"), Date())]])
        #expect(WallpaperStore.references(directory: dir, in: swapped))
        #expect(!WallpaperStore.references(directory: dir, in: store(desktop: black, idle: aerial)))
        #expect(!WallpaperStore.references(directory: dir, in: store(desktop: image("/Users/Jane Doe/Pictures/cat.png"), idle: aerial)))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter WallpaperStoreTests`
Expected: build failure, `cannot find 'WallpaperStore' in scope`.

- [ ] **Step 3: Implement `WallpaperStore`**

Create `Sources/AmbientCore/WallpaperStore.swift`:

```swift
import Foundation

/// Reads macOS's wallpaper store just enough to back it up and put it back safely. The format is
/// undocumented, so anything unexpected means "don't touch".
public enum WallpaperStore {
    public static func url(userHome: URL) -> URL {
        userHome.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// The provider of the wallpaper chosen for every Space and display, e.g. "com.apple.wallpaper.choice.color",
    /// when the store is in a format we know.
    public static func desktopProvider(of data: Data) -> String? {
        guard let root = propertyList(data) as? [String: Any],
              let all = root["AllSpacesAndDisplays"] as? [String: Any],
              let desktop = all["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let provider = choices.first?["Provider"] as? String else { return nil }
        return provider
    }

    public static func isKnownFormat(_ data: Data) -> Bool { desktopProvider(of: data) != nil }

    /// Whether two stores choose the same wallpapers everywhere, ignoring when each was last set or used.
    public static func matches(_ a: Data, _ b: Data) -> Bool {
        guard let x = propertyList(a).map(normalized) as? [String: Any],
              let y = propertyList(b).map(normalized) as? [String: Any] else { return false }
        return NSDictionary(dictionary: x).isEqual(to: y)
    }

    /// Whether any choice in the store points into `directory`, i.e. an image Ambient set is still the wallpaper.
    public static func references(directory: URL, in data: Data) -> Bool {
        guard let root = propertyList(data) else { return false }
        let path = directory.standardizedFileURL.path
        var encoded = directory.standardizedFileURL.absoluteString
        if encoded.hasSuffix("/") { encoded.removeLast() }
        return mentions(normalized(root)) { $0.contains(path) || $0.contains(encoded) }
    }

    private static let timestampKeys: Set<String> = ["LastSet", "LastUse"]

    /// Drops timestamps and opens nested property lists (choices keep their configuration as encoded data),
    /// so two stores compare by what they choose.
    private static func normalized(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in dict where !timestampKeys.contains(key) { out[key] = normalized(inner) }
            return out
        }
        if let array = value as? [Any] { return array.map(normalized) }
        if let data = value as? Data, !data.isEmpty, let inner = propertyList(data) { return normalized(inner) }
        return value
    }

    private static func mentions(_ value: Any, _ test: (String) -> Bool) -> Bool {
        if let s = value as? String { return test(s) }
        if let dict = value as? [String: Any] { return dict.values.contains { mentions($0, test) } }
        if let array = value as? [Any] { return array.contains { mentions($0, test) } }
        return false
    }

    private static func propertyList(_ data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, format: nil)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WallpaperStoreTests && swift test`
Expected: all pass.

- [ ] **Step 5: Check against the real store (read-only)**

Run:

```bash
cat > /tmp/ws-check.swift <<'EOF'
import Foundation
let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
let data = try! Data(contentsOf: url)
let root = try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
let all = root["AllSpacesAndDisplays"] as! [String: Any]
let desktop = (all["Desktop"] as! [String: Any])["Content"] as! [String: Any]
print(((desktop["Choices"] as! [[String: Any]]).first!["Provider"])!)
EOF
swift /tmp/ws-check.swift
```

Expected: a provider name such as `com.apple.wallpaper.choice.color`. If this crashes, the real store has a different shape from the fixtures: stop and update the fixtures and the parser before going on.

- [ ] **Step 6: Commit**

```bash
git add Sources/AmbientCore/WallpaperStore.swift Tests/AmbientCoreTests/WallpaperStoreTests.swift
git commit -m "feat(core): read and compare macOS's wallpaper store"
```

---

### Task 4: Scene engine, Sky, preferences and the Wallpaper pane

**Files:**
- Modify: `Sources/AmbientApp/Preferences.swift`
- Create: `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`
- Create: `Sources/AmbientApp/Wallpaper/SceneView.swift`
- Create: `Sources/AmbientApp/Wallpaper/SkyScene.swift`
- Create: `Sources/AmbientApp/Settings/Previews/WallpaperPreview.swift`
- Create: `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- Create: `Sources/AmbientApp/Settings/Panes/ScenePicker.swift`
- Modify: `Sources/AmbientApp/Settings/SettingsPane.swift`
- Modify: `Sources/AmbientApp/Settings/SettingsView.swift`

**Interfaces:**
- Consumes:
  - from Task 2: `SceneState`, `SceneInhabitant`, `SceneSurface`, `SceneKind`, `SceneChoice`, `ScenePolicy`, `DayLight`, `DayPhase`, `GlowStyle.level(at:)`, `RGB.mixed`, `DayLog.maxMarks`;
  - from core: `Palette.agent/mood/waiting/error`;
  - `RGB.color` (`Colors.swift`), `PreviewStage`, `SettingsSection`, `SettingsToggleRow`, `PaneHeader`, `Theme`.
- Produces:
  - `protocol SceneRenderer { func spot(_:surface:) -> CGPoint; func draw(_:size:state:date:motion:) }`
  - `SceneRenderers.renderer(for:) -> any SceneRenderer`
  - `struct SceneMotion { var reduce; var still }`, `struct SceneRandom`
  - `GraphicsContext.fillGlow/fillCircle/fillVertical`
  - `glowLevel(_:date:motion:)`, `scenePoint(_:in:)`, `arrivalProgress(of:at:)`
  - `struct SceneView(state:showsText:animated:reduceMotion:)`
  - `Preferences.wallpaperEnabled/wallpaperScene/wallpaperOnLockScreen/wallpaperLockMessages/wallpaperCalendar`, `Preferences.sceneChoice`
  - `WallpaperPreview.state(_:now:)`, `WallpaperPreview.scenery(_:)`
  - `SettingsPane.wallpaper`

- [ ] **Step 1: Add the preferences**

In `Sources/AmbientApp/Preferences.swift`, add after the `setupCompleted` property:

```swift
    @Published var wallpaperEnabled: Bool { didSet { defaults.set(wallpaperEnabled, forKey: "wallpaperEnabled") } }
    /// "sky", "harbor", "garden" or "daily".
    @Published var wallpaperScene: String { didSet { defaults.set(wallpaperScene, forKey: "wallpaperScene") } }
    @Published var wallpaperOnLockScreen: Bool { didSet { defaults.set(wallpaperOnLockScreen, forKey: "wallpaperOnLockScreen") } }
    @Published var wallpaperLockMessages: Bool { didSet { defaults.set(wallpaperLockMessages, forKey: "wallpaperLockMessages") } }
    @Published var wallpaperCalendar: Bool { didSet { defaults.set(wallpaperCalendar, forKey: "wallpaperCalendar") } }
```

Add to the `register(defaults:)` dictionary:

```swift
            "wallpaperEnabled": false,
            "wallpaperScene": "daily",
            "wallpaperOnLockScreen": true,
            "wallpaperLockMessages": false,
            "wallpaperCalendar": false,
```

Add at the end of `init`:

```swift
        wallpaperEnabled = defaults.bool(forKey: "wallpaperEnabled")
        wallpaperScene = defaults.string(forKey: "wallpaperScene") ?? "daily"
        wallpaperOnLockScreen = defaults.bool(forKey: "wallpaperOnLockScreen")
        wallpaperLockMessages = defaults.bool(forKey: "wallpaperLockMessages")
        wallpaperCalendar = defaults.bool(forKey: "wallpaperCalendar")
```

Add after `alertSettings`:

```swift
    var sceneChoice: SceneChoice { SceneChoice(rawValue: wallpaperScene) ?? .daily }
```

- [ ] **Step 2: Create the renderer protocol and drawing helpers**

Create `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`:

```swift
import AmbientCore
import SwiftUI

/// How much a scene may move.
struct SceneMotion: Equatable {
    /// Reduce Motion: nothing drifts, sways or circles; glows still fade in and out.
    var reduce = false
    /// A still frame: covered, Low Power Mode, a thumbnail, or the lock-screen fallback image.
    var still = false
}

/// Draws one world. Spots are in unit coordinates: (0, 0) is the top-left corner, (1, 1) the bottom-right.
protocol SceneRenderer {
    /// Where inhabitant spot `slot` sits. Lock-screen spots stay clear of the lock screen's clock (top center)
    /// and password field (bottom center).
    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint
    func draw(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion)
}

enum SceneRenderers {
    static func renderer(for kind: SceneKind) -> any SceneRenderer {
        switch kind {
        // Harbor and Garden get their own renderers in Task 8; until then they show the sky.
        case .sky, .harbor, .garden: SkyScene()
        }
    }
}

/// Repeatable randomness (SplitMix64), so stars and fireflies sit in the same places every frame and every launch.
struct SceneRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

extension GraphicsContext {
    /// A soft light: `color` at the center, fading out by `radius`.
    func fillGlow(at center: CGPoint, radius: CGFloat, color: Color) {
        guard radius > 0 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let gradient = Gradient(stops: [
            .init(color: color, location: 0),
            .init(color: color.opacity(0.3), location: 0.3),
            .init(color: color.opacity(0), location: 1),
        ])
        fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
    }

    func fillCircle(at center: CGPoint, radius: CGFloat, color: Color) {
        fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
             with: .color(color))
    }

    /// A top-to-bottom gradient over `rect`. Stops are (location 0...1, color).
    func fillVertical(_ rect: CGRect, _ stops: [(Double, Color)]) {
        let gradient = Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0) })
        fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                               endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    }
}

/// How bright an inhabitant's glow is right now, in the Dock glow's rhythms. Failures flicker.
func glowLevel(_ inhabitant: SceneInhabitant, date: Date, motion: SceneMotion) -> Double {
    guard let style = GlowStyle.for(mood: inhabitant.mood, agent: inhabitant.agent) else { return 0.18 }
    if motion.still { return style.high }
    let t = date.timeIntervalSinceReferenceDate
    if inhabitant.mood == .error, !motion.reduce { return style.high * (sin(t * 7) > 0.7 ? 0.45 : 1) }
    return style.level(at: t)
}

/// A spot in unit coordinates, on a canvas of `size`.
func scenePoint(_ spot: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: spot.x * size.width, y: spot.y * size.height)
}

/// How far a just-finished turn has come on its way into the day's build-up: 0 → 1 over two seconds,
/// nil when nothing is arriving.
func arrivalProgress(of marks: [DayMark], at date: Date) -> Double? {
    guard let last = marks.last else { return nil }
    let age = date.timeIntervalSince(last.at)
    return age >= 0 && age < 2 ? age / 2 : nil
}
```

- [ ] **Step 3: Create the scene view and its text layer**

Create `Sources/AmbientApp/Wallpaper/SceneView.swift`:

```swift
import AmbientCore
import SwiftUI

/// A living wallpaper: one world, its inhabitants, and the text set into it.
struct SceneView: View {
    let state: SceneState
    /// False on displays other than the main one, and for thumbnails.
    var showsText = true
    /// False draws one still frame: while covered, in Low Power Mode, for thumbnails and for the lock-screen fallback image.
    var animated = true
    var reduceMotion = false

    var body: some View {
        let renderer = SceneRenderers.renderer(for: state.kind)
        if animated {
            TimelineView(.animation(minimumInterval: Self.frameInterval(state), paused: false)) { context in
                frame(renderer, date: context.date, motion: SceneMotion(reduce: reduceMotion, still: false))
            }
        } else {
            frame(renderer, date: state.now, motion: SceneMotion(reduce: reduceMotion, still: true))
        }
    }

    /// 30 frames a second while something moves; about one a second when everything rests.
    static func frameInterval(_ state: SceneState) -> Double {
        let moving = state.inhabitants.contains { $0.mood != .idle } || arrivalProgress(of: state.marks, at: Date()) != nil
        return moving ? 1.0 / 30 : 1
    }

    private func frame(_ renderer: any SceneRenderer, date: Date, motion: SceneMotion) -> some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    renderer.draw(&ctx, size: size, state: state, date: date, motion: motion)
                }
                if showsText {
                    SceneTextLayer(state: state, renderer: renderer, size: geo.size)
                }
            }
        }
    }
}

/// The words set into a scene: the clock and your day top-left, a label beside each inhabitant,
/// the day's story bottom-left and the latest moments bottom-right. Sizes follow the display.
struct SceneTextLayer: View {
    let state: SceneState
    let renderer: any SceneRenderer
    let size: CGSize

    /// 1 on a display 1000 points tall.
    private var u: CGFloat { min(1.6, size.height / 1000) }
    private var ink: Color { state.light.darkInk ? Color(white: 0.1) : .white }
    private var halo: Color { state.light.darkInk ? .white.opacity(0.45) : .black.opacity(0.5) }

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                header
                    .padding(.leading, size.width * 0.06)
                    .padding(.top, size.height * 0.10)
            }
            .overlay(alignment: .bottomLeading) {
                story
                    .padding(.leading, size.width * 0.06)
                    .padding(.bottom, size.height * 0.05)
            }
            .overlay(alignment: .bottomTrailing) {
                timeline
                    .padding(.trailing, size.width * 0.04)
                    .padding(.bottom, size.height * 0.045)
            }
            .overlay { labels }
            .foregroundStyle(ink)
            .shadow(color: halo, radius: 6 * u)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            if let clock = state.clock {
                Text(clock).font(.system(size: 54 * u, weight: .ultraLight)).monospacedDigit()
            }
            if let date = state.date {
                Text(date).font(.system(size: 14 * u)).opacity(0.85)
            }
            if let next = state.nextEvent {
                HStack(spacing: 6 * u) {
                    RoundedRectangle(cornerRadius: 2 * u)
                        .fill(Color(red: 1, green: 0.42, blue: 0.42))
                        .frame(width: 8 * u, height: 8 * u)
                    Text(next)
                }
                .font(.system(size: 12.5 * u))
                .opacity(0.85)
                .padding(.top, 4 * u)
            }
        }
    }

    private var labels: some View {
        ZStack {
            ForEach(state.inhabitants) { inhabitant in
                let spot = renderer.spot(inhabitant.slot, surface: state.surface)
                // Near the right edge, the label sits to the left of its inhabitant.
                let flipped = spot.x > 0.72
                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: flipped ? .trailing : .leading) {
                        label(inhabitant, flipped: flipped)
                            .fixedSize()
                            .padding(flipped ? .trailing : .leading, 22 * u)
                    }
                    .position(x: spot.x * size.width, y: spot.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func label(_ inhabitant: SceneInhabitant, flipped: Bool) -> some View {
        VStack(alignment: flipped ? .trailing : .leading, spacing: 2 * u) {
            Text(inhabitant.headline)
                .font(.system(size: 12.5 * u, weight: .semibold))
                .foregroundStyle(inhabitant.mood == .waiting ? Palette.waiting.color : ink)
            Text(inhabitant.place).font(.system(size: 12 * u)).opacity(0.75)
            if let detail = inhabitant.detail {
                Text(detail).font(.system(size: 11 * u, design: .monospaced)).opacity(0.6)
            }
        }
        .multilineTextAlignment(flipped ? .trailing : .leading)
    }

    /// "Today   3h 40m of agent time  ·  612 tools  ·  …", numbers in semibold.
    private var story: some View {
        HStack(spacing: 0) {
            if state.story.isEmpty {
                Text("A quiet day so far")
            } else {
                Text("Today   ")
                ForEach(Array(state.story.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Text("  ·  ") }
                    Text(item.value).fontWeight(.semibold)
                    Text(" " + item.label)
                }
            }
            if state.overflow > 0 {
                Text("   ·   +\(state.overflow) more " + (state.overflow == 1 ? "session" : "sessions") + " now")
            }
        }
        .font(.system(size: 12 * u))
        .opacity(0.85)
        .fixedSize()
    }

    private var timeline: some View {
        VStack(alignment: .trailing, spacing: 3 * u) {
            ForEach(Array(state.timeline.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8 * u) {
                    Text(line.time).font(.system(size: 10.5 * u, design: .monospaced)).opacity(0.75)
                    Text(line.text).font(.system(size: 10.5 * u))
                }
            }
        }
        .opacity(0.65)
    }
}
```

- [ ] **Step 4: Create Sky**

Create `Sources/AmbientApp/Wallpaper/SkyScene.swift`:

```swift
import AmbientCore
import SwiftUI

/// Every session is a star. Finished turns gather into a constellation across the sky; the Milky Way comes out at night.
struct SkyScene: SceneRenderer {
    private static let deskSpots: [CGPoint] = [
        CGPoint(x: 0.70, y: 0.40), CGPoint(x: 0.83, y: 0.57), CGPoint(x: 0.57, y: 0.60), CGPoint(x: 0.46, y: 0.44),
        CGPoint(x: 0.62, y: 0.30), CGPoint(x: 0.90, y: 0.36), CGPoint(x: 0.36, y: 0.62), CGPoint(x: 0.76, y: 0.70),
        CGPoint(x: 0.50, y: 0.72), CGPoint(x: 0.28, y: 0.48), CGPoint(x: 0.88, y: 0.72), CGPoint(x: 0.40, y: 0.34),
    ]
    /// Clear of the lock screen's clock (top center) and password field (bottom center).
    private static let lockSpots: [CGPoint] = [
        CGPoint(x: 0.74, y: 0.42), CGPoint(x: 0.84, y: 0.58), CGPoint(x: 0.26, y: 0.56), CGPoint(x: 0.16, y: 0.40),
        CGPoint(x: 0.68, y: 0.62), CGPoint(x: 0.88, y: 0.32), CGPoint(x: 0.34, y: 0.66), CGPoint(x: 0.12, y: 0.62),
        CGPoint(x: 0.78, y: 0.74), CGPoint(x: 0.22, y: 0.74), CGPoint(x: 0.92, y: 0.68), CGPoint(x: 0.30, y: 0.36),
    ]

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let spots = surface == .desk ? Self.deskSpots : Self.lockSpots
        return spots[((slot % spots.count) + spots.count) % spots.count]
    }

    private struct Look {
        let top, middle, horizon, glow, hills, near: RGB
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night:
            Look(top: RGB(hex: "#03050F"), middle: RGB(hex: "#0B1030"), horizon: RGB(hex: "#1A1E48"),
                 glow: RGB(hex: "#2A2F6A"), hills: RGB(hex: "#0A0B1C"), near: RGB(hex: "#05060F"))
        case .dawn:
            Look(top: RGB(hex: "#1D2352"), middle: RGB(hex: "#5B4A7E"), horizon: RGB(hex: "#E7A88A"),
                 glow: RGB(hex: "#F4C29B"), hills: RGB(hex: "#2A2748"), near: RGB(hex: "#15142A"))
        case .day:
            Look(top: RGB(hex: "#2F6FC8"), middle: RGB(hex: "#5C9BE3"), horizon: RGB(hex: "#B8DDF7"),
                 glow: RGB(hex: "#FFFFFF"), hills: RGB(hex: "#4A6E8F"), near: RGB(hex: "#2F4B63"))
        case .dusk:
            Look(top: RGB(hex: "#060A1D"), middle: RGB(hex: "#46336A"), horizon: RGB(hex: "#EEA56F"),
                 glow: RGB(hex: "#C06F5D"), hills: RGB(hex: "#161634"), near: RGB(hex: "#0A0A1A"))
        }
    }

    /// How much of the night sky shows: all of it at night, some at dusk and dawn, none by day.
    private static func starlight(_ phase: DayPhase) -> Double {
        switch phase {
        case .night: 1
        case .dusk: 0.55
        case .dawn: 0.3
        case .day: 0
        }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let light = state.light
        let u = size.height / 1000
        let t = date.timeIntervalSinceReferenceDate
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }

        ctx.fillVertical(CGRect(origin: .zero, size: size),
                         [(0, mix(\.top)), (0.45, mix(\.middle)), (0.82, mix(\.horizon)), (1, mix(\.horizon))])
        ctx.fillGlow(at: CGPoint(x: size.width * 0.3, y: size.height * 0.84), radius: 520 * u,
                     color: mix(\.glow).opacity(0.35))

        let stars = light.amount(Self.starlight)
        let night = light.amount { $0 == .night ? 1 : 0 }
        if night > 0.01 { milkyWay(&ctx, size: size, strength: night) }
        if stars > 0.01 {
            var rng = SceneRandom(seed: 7)
            for _ in 0..<180 {
                let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height * 0.72)
                let radius = CGFloat(0.5 + rng.next() * 1.1) * max(u, 0.6)
                let speed = 0.4 + rng.next(), offset = rng.next() * 6.3
                let twinkle = motion.still ? 0.75 : 0.55 + 0.45 * sin(t * speed + offset)
                ctx.fillCircle(at: p, radius: radius, color: .white.opacity(stars * twinkle * 0.85))
            }
        }

        constellation(&ctx, size: size, marks: state.marks, date: date, visibility: max(0.4, stars), u: u)

        for inhabitant in state.inhabitants {
            star(&ctx, inhabitant, at: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, date: date, motion: motion)
        }

        ctx.fill(hills(size, far: true), with: .color(mix(\.hills)))
        ctx.fill(hills(size, far: false), with: .color(mix(\.near)))
    }

    private func milkyWay(_ ctx: inout GraphicsContext, size: CGSize, strength: Double) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: size.height * 0.04))
            var rng = SceneRandom(seed: 42)
            for i in 0..<14 {
                let f = Double(i) / 13
                let x = size.width * CGFloat(0.15 + 0.8 * f)
                let y = size.height * CGFloat(0.6 - 0.5 * f + (rng.next() - 0.5) * 0.06)
                let w = size.width * CGFloat(0.10 + rng.next() * 0.08)
                let h = size.height * CGFloat(0.05 + rng.next() * 0.04)
                layer.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
                           with: .color(Color(red: 0.75, green: 0.78, blue: 1).opacity(0.10 * strength)))
            }
        }
    }

    /// Where the day's `index`th finished turn sits: along an arc across the upper sky, oldest first.
    private static func markPoint(_ index: Int, size: CGSize) -> CGPoint {
        var rng = SceneRandom(seed: UInt64(index) &+ 99)
        let f = Double(index) / Double(DayLog.maxMarks - 1)
        return CGPoint(x: size.width * CGFloat(0.38 + 0.56 * f),
                       y: size.height * CGFloat(0.40 - 0.32 * f + (rng.next() - 0.5) * 0.07))
    }

    private func constellation(_ ctx: inout GraphicsContext, size: CGSize, marks: [DayMark], date: Date,
                               visibility: Double, u: CGFloat) {
        guard !marks.isEmpty else { return }
        let points = marks.indices.map { Self.markPoint($0, size: size) }
        var line = Path()
        line.addLines(points)
        ctx.stroke(line, with: .color(.white.opacity(0.16 * visibility)), lineWidth: max(0.6, 1.2 * u))
        for (mark, p) in zip(marks, points) {
            let color = mark.outcome == .failed ? Palette.error : Palette.agent(mark.agent)
            ctx.fillCircle(at: p, radius: 3 * max(u, 0.5), color: color.color.opacity(0.75 * visibility))
        }
        // A turn that just finished streaks in and takes its place.
        if let f = arrivalProgress(of: marks, at: date), let p = points.last {
            let left = CGFloat(1 - f)
            let head = CGPoint(x: p.x + 220 * u * left, y: p.y + 140 * u * left)
            var streak = Path()
            streak.move(to: head)
            streak.addLine(to: CGPoint(x: head.x + 60 * u, y: head.y + 38 * u))
            ctx.stroke(streak, with: .color(.white.opacity(0.8 * (1 - f))), lineWidth: 2 * u)
            ctx.fillCircle(at: head, radius: 3 * u, color: .white.opacity(1 - f / 2))
        }
    }

    private func star(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at p: CGPoint, u: CGFloat,
                      date: Date, motion: SceneMotion) {
        let body = Palette.agent(inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)
        ctx.fillGlow(at: p, radius: CGFloat(80 + 40 * inhabitant.busyness) * u,
                     color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color.opacity(level))
        ctx.fillCircle(at: p, radius: 7 * u, color: .white.opacity(inhabitant.mood == .idle ? 0.5 : 0.95))
        ctx.fillCircle(at: p, radius: 3.5 * u, color: body)
        guard inhabitant.mood == .working else { return }
        // Sparks circle a working star, more as its turn does more.
        let sparks = 1 + Int(inhabitant.busyness * 4)
        let turn = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate * 1.4
        for k in 0..<sparks {
            let angle = turn + Double(k) * 2 * .pi / Double(sparks)
            let spark = CGPoint(x: p.x + CGFloat(cos(angle)) * 26 * u, y: p.y + CGFloat(sin(angle)) * 26 * u)
            ctx.fillCircle(at: spark, radius: 2.2 * u, color: body.opacity(0.9))
        }
    }

    private func hills(_ size: CGSize, far: Bool) -> Path {
        let w = size.width, h = size.height
        var p = Path()
        if far {
            p.move(to: CGPoint(x: 0, y: h * 0.80))
            p.addCurve(to: CGPoint(x: w * 0.375, y: h * 0.76), control1: CGPoint(x: w * 0.14, y: h * 0.745),
                       control2: CGPoint(x: w * 0.25, y: h * 0.78))
            p.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.745), control1: CGPoint(x: w * 0.5, y: h * 0.74),
                       control2: CGPoint(x: w * 0.6, y: h * 0.705))
            p.addCurve(to: CGPoint(x: w, y: h * 0.74), control1: CGPoint(x: w * 0.85, y: h * 0.785),
                       control2: CGPoint(x: w * 0.93, y: h * 0.79))
        } else {
            p.move(to: CGPoint(x: 0, y: h * 0.87))
            p.addCurve(to: CGPoint(x: w * 0.45, y: h * 0.84), control1: CGPoint(x: w * 0.16, y: h * 0.83),
                       control2: CGPoint(x: w * 0.3, y: h * 0.86))
            p.addCurve(to: CGPoint(x: w, y: h * 0.855), control1: CGPoint(x: w * 0.65, y: h * 0.81),
                       control2: CGPoint(x: w * 0.85, y: h * 0.875))
        }
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
```

- [ ] **Step 5: Create the preview**

Create `Sources/AmbientApp/Settings/Previews/WallpaperPreview.swift`:

```swift
import AmbientCore
import SwiftUI

/// The chosen world with three demo sessions: one needs you, one works, one is done.
struct WallpaperPreview: View {
    let enabled: Bool
    let choice: SceneChoice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PreviewStage(enabled: enabled) {
            TimelineView(.everyMinute) { context in
                SceneView(state: Self.state(ScenePolicy.kind(for: choice, on: context.date), now: context.date),
                          animated: enabled, reduceMotion: reduceMotion)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the living wallpaper")
    }

    static func state(_ kind: SceneKind, now: Date) -> SceneState {
        SceneState.make(sessions: sessions(now: now), day: DayLog(now: now), now: now, kind: kind, surface: .desk)
    }

    /// The world alone, for thumbnails.
    static func scenery(_ kind: SceneKind) -> SceneState { state(kind, now: Date()).scenery() }

    private static func sessions(now: Date) -> [Session] {
        func session(_ id: String, _ agent: AgentKind, _ project: String, _ activity: Activity, tools: Int) -> Session {
            var s = Session(agent: agent, sessionId: "preview-\(id)", at: now)
            s.cwd = "/preview/\(project)"
            s.activity = activity
            s.toolCount = tools
            s.turnStartedAt = now.addingTimeInterval(-600)
            s.activitySince = now.addingTimeInterval(-120)
            if case .done = activity { s.turnEndedAt = now.addingTimeInterval(-240) }
            return s
        }
        return [
            session("a", .claude, "api-server", .waiting(reason: "permission", message: "Bash: rm -rf build"), tools: 12),
            session("b", .codex, "web", .tool(name: "Bash", detail: "npm test"), tools: 48),
            session("c", .gemini, "docs", .done(summary: "Docs rebuilt"), tools: 20),
        ]
    }
}
```

- [ ] **Step 6: Create the pane and add it to Settings**

Create `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`:

```swift
import AmbientCore
import SwiftUI

struct WallpaperPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .wallpaper)
            WallpaperPreview(enabled: prefs.wallpaperEnabled, choice: prefs.sceneChoice)
            SettingsSection(footer: "Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.") {
                SettingsToggleRow(title: "Living wallpaper", isOn: $prefs.wallpaperEnabled)
            }
            SettingsSection(header: "Scene") {
                ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
            }
            .disabled(!prefs.wallpaperEnabled)
        }
    }
}
```

Create `Sources/AmbientApp/Settings/Panes/ScenePicker.swift`:

```swift
import AmbientCore
import SwiftUI

private struct SceneOption: Identifiable {
    let id: String
    let title: String
    /// Nil for "A new one each day".
    let kind: SceneKind?

    static let all: [SceneOption] = SceneKind.allCases.map { SceneOption(id: $0.rawValue, title: $0.displayName, kind: $0) }
        + [SceneOption(id: SceneChoice.daily.rawValue, title: "A new one each day", kind: nil)]
}

/// A card per world, and one for "A new one each day".
struct ScenePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            ForEach(SceneOption.all) { option in
                let selected = option.id == selection
                Button { selection = option.id } label: {
                    VStack(spacing: 6) {
                        thumbnail(option.kind)
                            .frame(height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Theme.Colors.hairline, lineWidth: selected ? 2 : 0.5))
                        Text(option.title)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func thumbnail(_ kind: SceneKind?) -> some View {
        if let kind {
            SceneView(state: WallpaperPreview.scenery(kind), showsText: false, animated: false)
        } else {
            HStack(spacing: 0) {
                ForEach(SceneKind.allCases, id: \.self) { kind in
                    SceneView(state: WallpaperPreview.scenery(kind), showsText: false, animated: false)
                }
            }
        }
    }
}
```

In `Sources/AmbientApp/Settings/SettingsPane.swift`:
- change the cases to `case welcome, agents, island, alerts, dock, wallpaper, general`;
- add `case .wallpaper: "Wallpaper"` to `title`;
- add `case .wallpaper: "photo.artframe"` to `symbol`;
- add `case .wallpaper: "A living world on your desktop and lock screen, where your agents live."` to `subtitle`.

In `Sources/AmbientApp/Settings/SettingsView.swift`, add to the `paneContent` switch before `.general`:

```swift
        case .wallpaper:
            WallpaperPane(prefs: prefs)
```

- [ ] **Step 7: Build, test and look at it**

Run: `swift build && swift test && scripts/build-app.sh --run`
Expected: build succeeds, tests pass, and Ambient launches.

Then open Settings (menu bar orb › Settings…) › **Wallpaper** and check:
- the preview shows the sky for the current time of day, with three stars: amber (needs you), teal-green with circling sparks (working), and green (done);
- the four scene cards render (Harbor and Garden look like Sky until Task 8);
- turning **Living wallpaper** off veils the preview with "Off".

Take a screenshot of the pane for the record: `screencapture -x -R0,0,1512,982 /tmp/wallpaper-pane.png`.

- [ ] **Step 8: Commit**

```bash
git add Sources/AmbientApp/Preferences.swift Sources/AmbientApp/Wallpaper Sources/AmbientApp/Settings
git commit -m "feat(app): scene engine, Sky, and the Wallpaper settings pane"
```

---

### Task 5: The wallpaper at the desk

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/SceneFeed.swift`
- Create: `Sources/AmbientApp/Wallpaper/DesktopLayer.swift`
- Create: `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `SceneView` (Task 4), `SceneState.make(...keeping:)` (Task 2), `AppModel.$sessions`, `AppModel.$day` (Task 1), `Preferences.wallpaperEnabled/sceneChoice` (Task 4).
- Produces:
  - `final class SceneFeed: ObservableObject { desk, lock: SceneState?; deskAnimated, lockAnimated, reduceMotion: Bool }`
  - `struct SceneHost(feed:surface:isMain:)`
  - `final class WallpaperWindow: NSWindow` with `convenience init(screen: NSScreen)`
  - `final class DesktopLayer { init(feed:); var isInstalled; var isVisible; var onVisibilityChange: (() -> Void)?; func install(); func uninstall() }`
  - `final class LivingWallpaper: ObservableObject { let feed: SceneFeed; init(model:prefs:paths:); func start(); func refresh() }`

- [ ] **Step 1: Create the feed, host and window**

Create `Sources/AmbientApp/Wallpaper/SceneFeed.swift`:

```swift
import AmbientCore
import AppKit
import Combine
import SwiftUI

/// What the wallpaper windows draw. Every window observes the same feed.
final class SceneFeed: ObservableObject {
    @Published var desk: SceneState?
    @Published var lock: SceneState?
    @Published var deskAnimated = false
    @Published var lockAnimated = false
    @Published var reduceMotion = false
}

/// One display's wallpaper: the full scene on the main display, the world alone elsewhere.
struct SceneHost: View {
    @ObservedObject var feed: SceneFeed
    let surface: SceneSurface
    let isMain: Bool

    var body: some View {
        if let state = surface == .desk ? feed.desk : feed.lock {
            SceneView(state: isMain ? state : state.scenery(), showsText: isMain,
                      animated: surface == .desk ? feed.deskAnimated : feed.lockAnimated,
                      reduceMotion: feed.reduceMotion)
        } else {
            Color.black
        }
    }
}

/// A borderless, click-through window that never becomes key or main: the wallpaper can't take focus.
final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        backgroundColor = .black
        setFrame(screen.frame, display: false)
    }
}
```

- [ ] **Step 2: Create the desktop layer**

Create `Sources/AmbientApp/Wallpaper/DesktopLayer.swift`:

```swift
import AppKit
import SwiftUI

/// The living wallpaper at the desk: a click-through window per display, just above the real wallpaper and
/// below Finder's icons, on every Space. Nothing to restore: removing the windows is all it takes.
final class DesktopLayer {
    private let feed: SceneFeed
    private var windows: [WallpaperWindow] = []
    private var observers: [NSObjectProtocol] = []
    /// Called when a window is covered or uncovered.
    var onVisibilityChange: (() -> Void)?

    init(feed: SceneFeed) { self.feed = feed }

    var isInstalled: Bool { !windows.isEmpty }

    /// Whether any part of the wallpaper can be seen right now.
    var isVisible: Bool { windows.contains { $0.occlusionState.contains(.visible) } }

    /// (Re)creates one window per display.
    func install() {
        uninstall()
        let main = NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.contentView = NSHostingView(rootView: SceneHost(feed: feed, surface: .desk, isMain: screen == main))
            window.orderFrontRegardless()
            windows.append(window)
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.onVisibilityChange?() })
        }
    }

    func uninstall() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}
```

- [ ] **Step 3: Create the coordinator (desk only)**

Create `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`:

```swift
import AmbientCore
import AppKit
import Combine
import os

/// Runs the living wallpaper: builds what the scene shows and decides where it's drawn.
final class LivingWallpaper: ObservableObject {
    let feed = SceneFeed()

    private let model: AppModel
    private let prefs: Preferences
    private let desktop: DesktopLayer
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var minuteTimer: Timer?
    private var slots: [String: Int] = [:]
    private var screensAsleep = false

    init(model: AppModel, prefs: Preferences, paths: AmbientPaths) {
        self.model = model
        self.prefs = prefs
        desktop = DesktopLayer(feed: feed)
        desktop.onVisibilityChange = { [weak self] in self?.updateMotion() }
    }

    func start() {
        model.$sessions.combineLatest(model.$day)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        // objectWillChange fires before the new value lands; hopping to the next turn of the run loop reads it.
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensChanged()
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
            center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
                self?.updateMotion()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
        ]
        scheduleMinuteTick()
        refresh()
    }

    // MARK: - What the scene shows

    /// Rebuilds the scene: on every change, and at the top of every minute for the clock and the light.
    func refresh() {
        guard prefs.wallpaperEnabled else { return turnOff() }
        let now = Date()
        let kind = ScenePolicy.kind(for: prefs.sceneChoice, on: now)
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   keeping: slots)
        slots = Dictionary(uniqueKeysWithValues: desk.inhabitants.map { ($0.id, $0.slot) })
        feed.desk = desk
        if !desktop.isInstalled { desktop.install() }
        updateMotion()
    }

    private func turnOff() {
        guard desktop.isInstalled || feed.desk != nil else { return }
        desktop.uninstall()
        feed.desk = nil
    }

    // MARK: - Motion, displays and time

    private func updateMotion() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let desk = desktop.isVisible && !screensAsleep && !lowPower
        if feed.reduceMotion != reduce { feed.reduceMotion = reduce }
        if feed.deskAnimated != desk { feed.deskAnimated = desk }
    }

    private func screensChanged() {
        guard prefs.wallpaperEnabled else { return }
        desktop.install()
        updateMotion()
    }

    private func clockChanged() {
        scheduleMinuteTick()
        refresh()
    }

    private func scheduleMinuteTick() {
        minuteTimer?.invalidate()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }
}
```

- [ ] **Step 4: Start it from the app delegate**

In `Sources/AmbientApp/AppDelegate.swift`:

Add below `private var dockGlow: DockGlow?`:

```swift
    private var wallpaper: LivingWallpaper?
```

In `applicationDidFinishLaunching`, after `dockGlow?.start()`:

```swift
        let wallpaper = LivingWallpaper(model: model, prefs: prefs, paths: paths)
        wallpaper.start()
        self.wallpaper = wallpaper
```

- [ ] **Step 5: Build and check it on the desktop**

Run: `swift build && scripts/build-app.sh --run`

Then, with Settings › Wallpaper › **Living wallpaper** on, check each of these:
1. Hide every window (Cmd-Option-H, then Cmd-H on the frontmost app). The sky fills the desktop, with the clock and date top-left.
2. Put a file on the desktop. Its icon shows **above** the sky, and clicking it selects it. Clicking empty desktop still works, including "click wallpaper to reveal desktop".
3. Switch Spaces (Ctrl-→). The sky is on every Space.
4. Run `~/.ambient/bin/ambient demo`. Stars appear with labels, needs-you pulses amber, and the story and timeline fill in as turns finish. Labels near the right edge sit to the left of their star, and none run off-screen.
5. **CPU:**
   - With the desktop showing and the demo running: `top -l 3 -s 2 -pid $(pgrep -x Ambient) -stats cpu | tail -1` shows under 2 %.
   - With a full-screen-sized window covering the desktop, it's close to 0.
6. **Displays** (Review Focus 2): change resolution in System Settings › Displays, or connect or disconnect a display. The sky refills every display.
7. Turn **Living wallpaper** off. Your own wallpaper is there immediately.

- [ ] **Step 6: Commit**

```bash
git add Sources/AmbientApp/Wallpaper Sources/AmbientApp/AppDelegate.swift
git commit -m "feat(app): living wallpaper at the desk"
```

---

### Task 6: The lock screen, live (SkyLight)

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/LockMonitor.swift`
- Create: `Sources/AmbientApp/Wallpaper/SkyLight.swift`
- Create: `Sources/AmbientApp/Wallpaper/LockLayer.swift`
- Replace: `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- Replace: `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- Modify: `Sources/AmbientApp/Settings/SettingsView.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `SceneFeed`, `SceneHost`, `WallpaperWindow`, `DesktopLayer` (Task 5); `Preferences.wallpaperOnLockScreen/wallpaperLockMessages` (Task 4).
- Produces:
  - `final class LockMonitor { @Published private(set) var isLocked: Bool; func start(); static func screenIsLocked() -> Bool }`
  - `final class SkyLight { static let shared: SkyLight?; static let lockScreenLevel: Int32; func makeLockScreenSpace() -> Int32?; func move(_: NSWindow, to: Int32) }`
  - `final class LockLayer { init(feed:skyLight:); var isInstalled; @discardableResult func install() -> Bool; func uninstall(); func show(onNotVisible:); func hide() }`
  - `LivingWallpaper.LockMode { off, live, swap, unavailable }`, `@Published lockMode`
  - `SettingsView(..., wallpaper: LivingWallpaper, ...)`, `WallpaperPane(prefs:wallpaper:)`

- [ ] **Step 1: Create the lock monitor**

Create `Sources/AmbientApp/Wallpaper/LockMonitor.swift`:

```swift
import AppKit
import Combine

/// Whether the screen is locked. A lock counts once it has held for two seconds, because Ctrl-Cmd-Q briefly
/// reports lock → unlock → lock. An unlock counts at once, so nothing lingers over the desktop.
final class LockMonitor {
    @Published private(set) var isLocked: Bool
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private static let settle: TimeInterval = 2

    init() { isLocked = Self.screenIsLocked() }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.lockReported()
            },
            center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.unlockReported()
            },
        ]
    }

    private func lockReported() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isLocked else { return }
            self.isLocked = true
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    private func unlockReported() {
        pending?.cancel()
        pending = nil
        if isLocked { isLocked = false }
    }

    static func screenIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
```

- [ ] **Step 2: Create the SkyLight wrapper**

Create `Sources/AmbientApp/Wallpaper/SkyLight.swift`:

```swift
import AppKit

/// The private SkyLight calls that put a window above the lock screen, resolved at runtime: a macOS
/// without them means no live lock screen, never a crash. Proven on macOS 27 in the 2026-09-29 spike.
final class SkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// Nil when this macOS doesn't have the calls.
    static let shared = SkyLight()

    /// Above the lock screen. Level 100 is not.
    static let lockScreenLevel: Int32 = 400

    private let mainConnection: MainConnectionID
    private let spaceCreate: SpaceCreate
    private let setLevel: SpaceSetAbsoluteLevel
    private let showSpaces: ShowSpaces
    private let addWindows: SpaceAddWindows

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? { dlsym(handle, name).map { unsafeBitCast($0, to: T.self) } }
        guard let main = symbol("SLSMainConnectionID", MainConnectionID.self),
              let create = symbol("SLSSpaceCreate", SpaceCreate.self),
              let level = symbol("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", ShowSpaces.self),
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", SpaceAddWindows.self) else { return nil }
        mainConnection = main
        spaceCreate = create
        setLevel = level
        showSpaces = show
        addWindows = add
    }

    /// A space above the lock screen, shown. Nil if SkyLight refused one.
    func makeLockScreenSpace() -> Int32? {
        let cid = mainConnection()
        let space = spaceCreate(cid, 1, 0)
        guard space != 0 else { return nil }
        _ = setLevel(cid, space, Self.lockScreenLevel)
        _ = showSpaces(cid, [space] as CFArray)
        return space
    }

    func move(_ window: NSWindow, to space: Int32) {
        _ = addWindows(mainConnection(), space, [window.windowNumber] as CFArray, 7)
    }
}
```

- [ ] **Step 3: Create the lock layer**

Create `Sources/AmbientApp/Wallpaper/LockLayer.swift`:

```swift
import AmbientCore
import AppKit
import SwiftUI

/// The living wallpaper on the lock screen, live: a window per display in a SkyLight space above the lock
/// screen. That space floats above everything, so the windows stay invisible and click-through until the Mac locks.
final class LockLayer {
    private let feed: SceneFeed
    private let skyLight: SkyLight
    private var space: Int32?
    private var windows: [WallpaperWindow] = []
    private var check: DispatchWorkItem?

    init(feed: SceneFeed, skyLight: SkyLight) {
        self.feed = feed
        self.skyLight = skyLight
    }

    var isInstalled: Bool { !windows.isEmpty }

    /// (Re)creates the windows, hidden. False if SkyLight refused a space.
    @discardableResult
    func install() -> Bool {
        uninstall()
        if space == nil { space = skyLight.makeLockScreenSpace() }
        guard let space else { return false }
        let main = NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.isOpaque = false
            window.alphaValue = 0
            window.contentView = NSHostingView(rootView: SceneHost(feed: feed, surface: .lock, isMain: screen == main))
            window.orderFrontRegardless()
            skyLight.move(window, to: space)
            windows.append(window)
        }
        return true
    }

    func uninstall() {
        check?.cancel()
        windows.forEach {
            $0.alphaValue = 0
            $0.orderOut(nil)
        }
        windows = []
    }

    /// Fades in over the lock screen, then checks that it can actually be seen; `onNotVisible` runs if not.
    func show(onNotVisible: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        check?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.windows.isEmpty else { return }
            if !self.windows.contains(where: { $0.occlusionState.contains(.visible) }) { onNotVisible() }
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Gone at once.
    func hide() {
        check?.cancel()
        windows.forEach { $0.alphaValue = 0 }
    }
}
```

- [ ] **Step 4: Replace the coordinator with the desk-and-lock version**

Replace the whole of `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift` with:

```swift
import AmbientCore
import AppKit
import Combine
import os

/// Runs the living wallpaper: builds what the scene shows and decides where it's drawn. At the desk, a layer of
/// windows; on the lock screen, windows in a SkyLight space above it.
final class LivingWallpaper: ObservableObject {
    enum LockMode: Equatable {
        /// The feature or the lock-screen option is off.
        case off
        /// Drawn live above the lock screen.
        case live
        /// Set as the real wallpaper while locked, and put back on unlock.
        case swap
        /// Neither works on this Mac.
        case unavailable
    }

    @Published private(set) var lockMode: LockMode = .off

    let feed = SceneFeed()

    private let model: AppModel
    private let prefs: Preferences
    private let desktop: DesktopLayer
    private let lockMonitor = LockMonitor()
    private var lockLayer: LockLayer?
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var minuteTimer: Timer?
    private var slots: [String: Int] = [:]
    private var screensAsleep = false
    private var locked = false

    /// The macOS build the live lock screen failed on; the fallback is used until the build changes.
    private static let fallbackBuildKey = "wallpaperLockFallbackBuild"
    /// Debug: `defaults write com.viveky259259.Ambient AmbientForceWallpaperSwap -bool true` skips the live layer.
    private static let forceSwapKey = "AmbientForceWallpaperSwap"
    private static var osBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    init(model: AppModel, prefs: Preferences, paths: AmbientPaths) {
        self.model = model
        self.prefs = prefs
        desktop = DesktopLayer(feed: feed)
        desktop.onVisibilityChange = { [weak self] in self?.updateMotion() }
    }

    func start() {
        model.$sessions.combineLatest(model.$day)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        // objectWillChange fires before the new value lands; hopping to the next turn of the run loop reads it.
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        locked = lockMonitor.isLocked
        lockMonitor.$isLocked
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lockChanged($0) }
            .store(in: &cancellables)
        lockMonitor.start()

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensChanged()
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
            center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
                self?.updateMotion()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
        ]
        scheduleMinuteTick()
        refresh()
    }

    // MARK: - What the scene shows

    /// Rebuilds the scene: on every change, and at the top of every minute for the clock and the light.
    func refresh() {
        guard prefs.wallpaperEnabled else { return turnOff() }
        let now = Date()
        let kind = ScenePolicy.kind(for: prefs.sceneChoice, on: now)
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   keeping: slots)
        slots = Dictionary(uniqueKeysWithValues: desk.inhabitants.map { ($0.id, $0.slot) })
        feed.desk = desk
        feed.lock = prefs.wallpaperOnLockScreen
            ? SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .lock,
                              lockMessages: prefs.wallpaperLockMessages, keeping: slots)
            : nil
        if !desktop.isInstalled { desktop.install() }
        updateLockMode()
        updateMotion()
    }

    private func turnOff() {
        desktop.uninstall()
        lockLayer?.uninstall()
        if feed.desk != nil { feed.desk = nil }
        if feed.lock != nil { feed.lock = nil }
        if lockMode != .off { lockMode = .off }
    }

    // MARK: - Lock screen

    private var liveLockAvailable: Bool {
        !UserDefaults.standard.bool(forKey: Self.forceSwapKey) && SkyLight.shared != nil
            && UserDefaults.standard.string(forKey: Self.fallbackBuildKey) != Self.osBuild
    }

    private func updateLockMode() {
        let mode: LockMode
        if !prefs.wallpaperEnabled || !prefs.wallpaperOnLockScreen {
            mode = .off
        } else {
            mode = liveLockAvailable ? .live : .unavailable
        }
        if mode != lockMode { lockMode = mode }
    }

    private func lockChanged(_ isLocked: Bool) {
        locked = isLocked
        updateMotion()
        if isLocked { enterLock() } else { leaveLock() }
    }

    private func enterLock() {
        guard prefs.wallpaperEnabled, prefs.wallpaperOnLockScreen else { return }
        guard liveLockAvailable, let skyLight = SkyLight.shared else { return }
        if lockLayer == nil { lockLayer = LockLayer(feed: feed, skyLight: skyLight) }
        guard let lockLayer, lockLayer.isInstalled || lockLayer.install() else {
            return fallBack(because: "SkyLight refused a space")
        }
        lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
    }

    private func leaveLock() {
        lockLayer?.hide()
    }

    /// The live layer can't show here: remember that for this macOS build.
    private func fallBack(because reason: String) {
        log.notice("Live lock screen unavailable (\(reason, privacy: .public)) on \(Self.osBuild, privacy: .public)")
        UserDefaults.standard.set(Self.osBuild, forKey: Self.fallbackBuildKey)
        lockLayer?.uninstall()
        lockLayer = nil
        updateLockMode()
    }

    // MARK: - Motion, displays and time

    private func updateMotion() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let desk = desktop.isVisible && !screensAsleep && !lowPower && !locked
        let lock = locked && !screensAsleep && !lowPower
        if feed.reduceMotion != reduce { feed.reduceMotion = reduce }
        if feed.deskAnimated != desk { feed.deskAnimated = desk }
        if feed.lockAnimated != lock { feed.lockAnimated = lock }
    }

    private func screensChanged() {
        guard prefs.wallpaperEnabled else { return }
        desktop.install()
        if let lockLayer, lockLayer.isInstalled {
            lockLayer.install()   // starts hidden
            if locked, lockMode == .live {
                lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
            }
        }
        updateMotion()
    }

    private func clockChanged() {
        scheduleMinuteTick()
        refresh()
    }

    private func scheduleMinuteTick() {
        minuteTimer?.invalidate()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }
}
```

- [ ] **Step 5: Give the pane the lock-screen settings**

Replace the whole of `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift` with:

```swift
import AmbientCore
import SwiftUI

struct WallpaperPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var wallpaper: LivingWallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .wallpaper)
            WallpaperPreview(enabled: prefs.wallpaperEnabled, choice: prefs.sceneChoice)
            SettingsSection(footer: "Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.") {
                SettingsToggleRow(title: "Living wallpaper", isOn: $prefs.wallpaperEnabled)
            }
            Group {
                SettingsSection(header: "Scene") {
                    ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
                }
                SettingsSection(header: "Lock screen") {
                    SettingsToggleRow(title: "Show on the lock screen", subtitle: lockStatus?.text,
                                      subtitleStatus: lockStatus?.status ?? .neutral, isOn: $prefs.wallpaperOnLockScreen)
                    SettingsDivider()
                    SettingsToggleRow(title: "Show messages on the lock screen",
                                      subtitle: "Prompts, summaries, command hints and event titles. Anyone near your Mac can read them.",
                                      isOn: $prefs.wallpaperLockMessages)
                        .disabled(!prefs.wallpaperOnLockScreen)
                }
            }
            .disabled(!prefs.wallpaperEnabled)
        }
    }

    private var lockStatus: (text: String, status: Theme.Status)? {
        switch wallpaper.lockMode {
        case .off: nil
        case .live: (text: "Live above the lock screen", status: .success)
        case .swap: (text: "Shown as your wallpaper while locked, then put back", status: .neutral)
        case .unavailable: (text: "Not available on this Mac", status: .warning)
        }
    }
}
```

In `Sources/AmbientApp/Settings/SettingsView.swift`:
- add `let wallpaper: LivingWallpaper` below `@ObservedObject var prefs: Preferences`;
- change the pane case to `WallpaperPane(prefs: prefs, wallpaper: wallpaper)`.

In `Sources/AmbientApp/AppDelegate.swift`, in `showSetup()`:
- change `if setupWindow == nil, let notifier {` to `if setupWindow == nil, let notifier, let wallpaper {`;
- change `SettingsView(setup: setup, prefs: prefs,` to `SettingsView(setup: setup, prefs: prefs, wallpaper: wallpaper,`.

- [ ] **Step 6: Build and check the lock screen**

Run: `swift build && scripts/build-app.sh --run`

Then:
1. With Living wallpaper on, run `~/.ambient/bin/ambient demo`. Settings › Wallpaper shows "Live above the lock screen".
2. Press Ctrl-Cmd-Q and keep your hands off the keyboard, trackpad and Touch ID (waking the display can unlock the Mac through Touch ID or an Apple Watch). Within about 3 s the scene fades in over the lock screen, and the star labels are there. Check:
   - no clock or date of ours (macOS's own clock is at the top);
   - nothing sits on the clock or the password field;
   - no command hints or messages under the labels.
3. Unlock. The scene disappears at once; nothing floats over the desktop or your windows.
4. Turn on **Show messages on the lock screen** and lock again: the hints and messages now show.
5. Change a display's resolution while unlocked (Review Focus 2). Nothing appears over the desktop.
6. Check the log has no fallback notice: `log show --last 10m --predicate 'subsystem == "com.viveky259259.Ambient" && category == "wallpaper"'`.
7. Check the unavailable state. Stash this build as the failed one, then relaunch:

   ```bash
   defaults write com.viveky259259.Ambient wallpaperLockFallbackBuild "$(osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSProcessInfo.processInfo.operatingSystemVersionString.js')"
   ```

   Settings says "Not available on this Mac". Then undo it with `defaults delete com.viveky259259.Ambient wallpaperLockFallbackBuild` and relaunch.

- [ ] **Step 7: Commit**

```bash
git add Sources/AmbientApp/Wallpaper Sources/AmbientApp/Settings Sources/AmbientApp/AppDelegate.swift
git commit -m "feat(app): living wallpaper on the lock screen, live"
```

---

### Task 7: The lock-screen fallback: swap the wallpaper while locked, put it back after

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`
- Replace: `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- Replace: `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`

**Interfaces:**
- Consumes:
  - `WallpaperStore.url/isKnownFormat/matches/references` (Task 3);
  - `AmbientPaths.home/backups/userHome`;
  - `SceneView` (Task 4);
  - the Task 6 coordinator.
- Produces:
  - `final class WallpaperSwap`:
    - `init(paths:)`
    - `var restorePending`, `var isSupported`
    - `func begin() -> Bool`
    - `func show(_ images: [(screen: NSScreen, png: Data)])`
    - `func restore(completion: @escaping (Bool) -> Void)`
    - `@MainActor static func render(_:for:showsText:) -> Data?`
  - `LivingWallpaper.restorePending` (`@Published`), `LivingWallpaper.restoreWallpaper()`

- [ ] **Step 1: Create the swap**

Create `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`:

```swift
import AmbientCore
import AppKit
import SwiftUI
import os

/// The lock-screen fallback. While the Mac is locked, the scene becomes the real wallpaper; on unlock, the user's
/// own wallpaper comes back exactly, from a backup of macOS's wallpaper store. The public API can't restore a
/// color or aerial wallpaper, which is why this backs up and restores the store itself.
final class WallpaperSwap {
    private let paths: AmbientPaths
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.wallpaper", qos: .userInitiated)

    init(paths: AmbientPaths) { self.paths = paths }

    var storeURL: URL { WallpaperStore.url(userHome: paths.userHome) }
    var backupURL: URL { paths.backups.appendingPathComponent("wallpaper-Index.plist") }
    var markerURL: URL { paths.home.appendingPathComponent("wallpaper-swapped") }
    var imagesDir: URL { paths.home.appendingPathComponent("wallpaper", isDirectory: true) }

    /// A swap started and hasn't been undone, e.g. Ambient quit while the Mac was locked.
    var restorePending: Bool { FileManager.default.fileExists(atPath: markerURL.path) }

    /// Whether the user's wallpaper store is one this knows how to put back.
    var isSupported: Bool { (try? Data(contentsOf: storeURL)).map(WallpaperStore.isKnownFormat) ?? false }

    /// Backs up the store and marks the swap. False when the store isn't in a format we know, or can't be backed up.
    func begin() -> Bool {
        // The backup from an unfinished swap is the user's real wallpaper; don't overwrite it with ours.
        if restorePending { return true }
        do {
            let data = try Data(contentsOf: storeURL)
            guard WallpaperStore.isKnownFormat(data) else {
                log.error("Wallpaper store format not recognized; not swapping")
                return false
            }
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: backupURL, options: .atomic)
            try Data().write(to: markerURL, options: .atomic)
            return true
        } catch {
            log.error("Couldn't back up the wallpaper store: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Sets one image per screen as the wallpaper. Each gets a new name, since macOS caches by URL.
    func show(_ images: [(screen: NSScreen, png: Data)]) {
        let previous = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        for (screen, png) in images {
            let url = imagesDir.appendingPathComponent("scene-\(UUID().uuidString).png")
            do {
                try png.write(to: url, options: .atomic)
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
                ])
            } catch {
                log.error("Couldn't set the lock-screen scene: \(error.localizedDescription, privacy: .public)")
            }
        }
        for url in previous { try? FileManager.default.removeItem(at: url) }
    }

    /// Puts the user's wallpaper back, off the main thread; `completion` runs on the main queue with whether the
    /// store now matches the backup.
    func restore(completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            let ok = restoreNow()
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private func restoreNow() -> Bool {
        guard restorePending else { return true }
        guard let backup = try? Data(contentsOf: backupURL) else {
            log.error("Wallpaper backup is missing; Settings will offer to restore")
            return false
        }
        // If none of Ambient's images is set any more (the user picked a new wallpaper after a crash), keep theirs.
        if let current = try? Data(contentsOf: storeURL), !WallpaperStore.references(directory: imagesDir, in: current) {
            cleanUp()
            return true
        }
        do {
            try backup.write(to: storeURL, options: .atomic)
        } catch {
            log.error("Couldn't restore the wallpaper store: \(error.localizedDescription, privacy: .public)")
            return false
        }
        restartWallpaperAgent()
        // The agent rewrites the store as it starts; give it a few seconds, then check it took.
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            if let now = try? Data(contentsOf: storeURL), WallpaperStore.matches(now, backup) {
                cleanUp()
                return true
            }
        }
        log.error("The wallpaper store doesn't match the backup after restoring")
        return false
    }

    private func restartWallpaperAgent() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["WallpaperAgent"]
        try? killall.run()
        killall.waitUntilExit()
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: markerURL)
        let images = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        for url in images { try? FileManager.default.removeItem(at: url) }
    }

    /// A PNG of a scene at a screen's native pixel size.
    @MainActor static func render(_ state: SceneState, for screen: NSScreen, showsText: Bool) -> Data? {
        let view = SceneView(state: state, showsText: showsText, animated: false)
            .frame(width: screen.frame.width, height: screen.frame.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = screen.backingScaleFactor
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 2: Replace the coordinator with the version that swaps**

Replace the whole of `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift` with:

```swift
import AmbientCore
import AppKit
import Combine
import os

/// Runs the living wallpaper: builds what the scene shows and decides where it's drawn. At the desk, a layer of
/// windows; on the lock screen, the SkyLight layer, or, where that can't show, the real wallpaper swapped while locked.
final class LivingWallpaper: ObservableObject {
    enum LockMode: Equatable {
        /// The feature or the lock-screen option is off.
        case off
        /// Drawn live above the lock screen.
        case live
        /// Set as the real wallpaper while locked, and put back on unlock.
        case swap
        /// Neither works on this Mac.
        case unavailable
    }

    @Published private(set) var lockMode: LockMode = .off
    /// A swapped wallpaper hasn't been put back yet.
    @Published private(set) var restorePending = false

    let feed = SceneFeed()

    private let model: AppModel
    private let prefs: Preferences
    private let desktop: DesktopLayer
    private let lockMonitor = LockMonitor()
    private var lockLayer: LockLayer?
    private let swap: WallpaperSwap
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "wallpaper")
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var minuteTimer: Timer?
    private var swapTimer: Timer?
    private var slots: [String: Int] = [:]
    private var screensAsleep = false
    private var locked = false
    private var swapping = false
    private var restoring = false
    private var lastSwap = Date.distantPast
    private var lastSwapMoods: [Mood] = []

    /// The macOS build the live lock screen failed on; the fallback is used until the build changes.
    private static let fallbackBuildKey = "wallpaperLockFallbackBuild"
    /// Debug: `defaults write com.viveky259259.Ambient AmbientForceWallpaperSwap -bool true` uses the fallback.
    private static let forceSwapKey = "AmbientForceWallpaperSwap"
    private static var osBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    init(model: AppModel, prefs: Preferences, paths: AmbientPaths) {
        self.model = model
        self.prefs = prefs
        desktop = DesktopLayer(feed: feed)
        swap = WallpaperSwap(paths: paths)
        desktop.onVisibilityChange = { [weak self] in self?.updateMotion() }
    }

    func start() {
        // A swap left behind by a crash or a forced quit is put right first.
        if swap.restorePending {
            restorePending = true
            if !LockMonitor.screenIsLocked() { restoreWallpaper() }
        }

        model.$sessions.combineLatest(model.$day)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        // objectWillChange fires before the new value lands; hopping to the next turn of the run loop reads it.
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        locked = lockMonitor.isLocked
        lockMonitor.$isLocked
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lockChanged($0) }
            .store(in: &cancellables)
        lockMonitor.start()

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensChanged()
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
            center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
                self?.updateMotion()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.clockChanged()
            },
            workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateMotion()
            },
        ]
        scheduleMinuteTick()
        refresh()
    }

    // MARK: - What the scene shows

    /// Rebuilds the scene: on every change, and at the top of every minute for the clock and the light.
    func refresh() {
        guard prefs.wallpaperEnabled else { return turnOff() }
        let now = Date()
        let kind = ScenePolicy.kind(for: prefs.sceneChoice, on: now)
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   keeping: slots)
        slots = Dictionary(uniqueKeysWithValues: desk.inhabitants.map { ($0.id, $0.slot) })
        feed.desk = desk
        feed.lock = prefs.wallpaperOnLockScreen
            ? SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .lock,
                              lockMessages: prefs.wallpaperLockMessages, keeping: slots)
            : nil
        if !desktop.isInstalled { desktop.install() }
        updateLockMode()
        updateMotion()
        swapIfMoodsChanged()
    }

    private func turnOff() {
        desktop.uninstall()
        lockLayer?.uninstall()
        if swapping { stopSwap() }
        if feed.desk != nil { feed.desk = nil }
        if feed.lock != nil { feed.lock = nil }
        if lockMode != .off { lockMode = .off }
    }

    // MARK: - Lock screen

    private var liveLockAvailable: Bool {
        !UserDefaults.standard.bool(forKey: Self.forceSwapKey) && SkyLight.shared != nil
            && UserDefaults.standard.string(forKey: Self.fallbackBuildKey) != Self.osBuild
    }

    private func updateLockMode() {
        let mode: LockMode
        if !prefs.wallpaperEnabled || !prefs.wallpaperOnLockScreen {
            mode = .off
        } else if liveLockAvailable {
            mode = .live
        } else {
            mode = swap.isSupported ? .swap : .unavailable
        }
        if mode != lockMode { lockMode = mode }
    }

    private func lockChanged(_ isLocked: Bool) {
        locked = isLocked
        updateMotion()
        if isLocked { enterLock() } else { leaveLock() }
    }

    private func enterLock() {
        guard prefs.wallpaperEnabled, prefs.wallpaperOnLockScreen else { return }
        guard liveLockAvailable, let skyLight = SkyLight.shared else { return startSwap() }
        if lockLayer == nil { lockLayer = LockLayer(feed: feed, skyLight: skyLight) }
        guard let lockLayer, lockLayer.isInstalled || lockLayer.install() else {
            return fallBack(because: "SkyLight refused a space")
        }
        lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
    }

    private func leaveLock() {
        lockLayer?.hide()
        if swapping {
            stopSwap()
        } else if swap.restorePending {
            restoreWallpaper()   // Retry a restore that failed earlier.
        }
    }

    /// The live layer can't show here: remember that for this macOS build and swap the wallpaper instead.
    private func fallBack(because reason: String) {
        log.notice("Live lock screen unavailable (\(reason, privacy: .public)) on \(Self.osBuild, privacy: .public); using the wallpaper swap")
        UserDefaults.standard.set(Self.osBuild, forKey: Self.fallbackBuildKey)
        lockLayer?.uninstall()
        lockLayer = nil
        updateLockMode()
        if locked { startSwap() }
    }

    // MARK: - Wallpaper swap (fallback)

    private func startSwap() {
        guard !swapping else { return }
        guard swap.begin() else {
            if lockMode != .unavailable { lockMode = .unavailable }
            return
        }
        swapping = true
        restorePending = true
        renderSwap()
        swapTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.renderSwap() }
    }

    private func renderSwap() {
        guard swapping, let state = feed.lock else { return }
        lastSwap = Date()
        lastSwapMoods = state.inhabitants.map(\.mood)
        let main = NSScreen.screens.first
        let images: [(screen: NSScreen, png: Data)] = MainActor.assumeIsolated {
            NSScreen.screens.compactMap { screen in
                let isMain = screen == main
                guard let png = WallpaperSwap.render(isMain ? state : state.scenery(), for: screen, showsText: isMain)
                else { return nil }
                return (screen: screen, png: png)
            }
        }
        swap.show(images)
    }

    /// While swapped, a change in anyone's mood redraws the wallpaper, at most every 8 seconds.
    private func swapIfMoodsChanged() {
        guard swapping, let state = feed.lock, state.inhabitants.map(\.mood) != lastSwapMoods,
              Date().timeIntervalSince(lastSwap) >= 8 else { return }
        renderSwap()
    }

    private func stopSwap() {
        swapTimer?.invalidate()
        swapTimer = nil
        swapping = false
        restoreWallpaper()
    }

    /// Puts the user's own wallpaper back. Also Settings' "Restore my wallpaper".
    func restoreWallpaper() {
        guard !restoring else { return }
        restoring = true
        swap.restore { [weak self] ok in
            guard let self else { return }
            self.restoring = false
            self.restorePending = !ok
            if !ok { self.log.error("Couldn't restore the wallpaper; Settings offers to try again") }
        }
    }

    // MARK: - Motion, displays and time

    private func updateMotion() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let desk = desktop.isVisible && !screensAsleep && !lowPower && !locked
        let lock = locked && !screensAsleep && !lowPower
        if feed.reduceMotion != reduce { feed.reduceMotion = reduce }
        if feed.deskAnimated != desk { feed.deskAnimated = desk }
        if feed.lockAnimated != lock { feed.lockAnimated = lock }
    }

    private func screensChanged() {
        guard prefs.wallpaperEnabled else { return }
        desktop.install()
        if let lockLayer, lockLayer.isInstalled {
            lockLayer.install()   // starts hidden
            if locked, lockMode == .live {
                lockLayer.show { [weak self] in self?.fallBack(because: "the lock-screen window wasn't visible") }
            }
        }
        if swapping { renderSwap() }
        updateMotion()
    }

    private func clockChanged() {
        scheduleMinuteTick()
        refresh()
    }

    private func scheduleMinuteTick() {
        minuteTimer?.invalidate()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }
}
```

- [ ] **Step 3: Offer "Restore my wallpaper" in the pane**

Replace the whole of `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift` with:

```swift
import AmbientCore
import SwiftUI

struct WallpaperPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var wallpaper: LivingWallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .wallpaper)
            WallpaperPreview(enabled: prefs.wallpaperEnabled, choice: prefs.sceneChoice)
            if wallpaper.restorePending {
                SettingsSection(footer: "Ambient showed the scene as your wallpaper while the Mac was locked and hasn't put yours back yet.") {
                    SettingsRow(title: "Restore my wallpaper") {
                        Button("Restore") { wallpaper.restoreWallpaper() }.buttonStyle(.pillProminent)
                    }
                }
            }
            SettingsSection(footer: "Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.") {
                SettingsToggleRow(title: "Living wallpaper", isOn: $prefs.wallpaperEnabled)
            }
            Group {
                SettingsSection(header: "Scene") {
                    ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
                }
                SettingsSection(header: "Lock screen") {
                    SettingsToggleRow(title: "Show on the lock screen", subtitle: lockStatus?.text,
                                      subtitleStatus: lockStatus?.status ?? .neutral, isOn: $prefs.wallpaperOnLockScreen)
                    SettingsDivider()
                    SettingsToggleRow(title: "Show messages on the lock screen",
                                      subtitle: "Prompts, summaries, command hints and event titles. Anyone near your Mac can read them.",
                                      isOn: $prefs.wallpaperLockMessages)
                        .disabled(!prefs.wallpaperOnLockScreen)
                }
            }
            .disabled(!prefs.wallpaperEnabled)
        }
    }

    private var lockStatus: (text: String, status: Theme.Status)? {
        switch wallpaper.lockMode {
        case .off: nil
        case .live: (text: "Live above the lock screen", status: .success)
        case .swap: (text: "Shown as your wallpaper while locked, then put back", status: .neutral)
        case .unavailable: (text: "Not available on this Mac", status: .warning)
        }
    }
}
```

- [ ] **Step 4: Build and check the fallback, including a crash**

Run: `swift build && swift test && scripts/build-app.sh --run`

Then:
1. Force the fallback and note the real wallpaper:

   ```bash
   defaults write com.viveky259259.Ambient AmbientForceWallpaperSwap -bool true
   pkill -x Ambient; open build/Ambient.app
   shasum ~/Library/Application\ Support/com.apple.wallpaper/Store/Index.plist
   ```

   Settings › Wallpaper shows "Shown as your wallpaper while locked, then put back".
2. Run `~/.ambient/bin/ambient demo`, press Ctrl-Cmd-Q and keep your hands off for about 40 s. The lock screen shows the scene as a still image, and it changes when a mood changes (at most every 8 s) or every 30 s.
3. Unlock. Then check:
   - `test -e ~/.ambient/wallpaper-swapped && echo still-marked || echo restored` prints `restored`;
   - `ls ~/.ambient/wallpaper/` is empty;
   - with Living wallpaper briefly off, your own wallpaper is on the desktop.
4. **Crash mid-lock:**
   - Run `(sleep 15; pkill -9 -x Ambient) &`, lock at once, and wait about 30 s, then unlock. The scene image is still your wallpaper and the marker exists.
   - `open build/Ambient.app`: within about 5 s your wallpaper is back and the marker is gone.
5. **Crash, then a new wallpaper (Review Focus 1):**
   - Repeat the crash, but before reopening Ambient, pick a different wallpaper in System Settings › Wallpaper.
   - Reopen Ambient: your new pick stays and the marker is gone.
   - Then set your original wallpaper back by hand.
6. Clean up: `defaults delete com.viveky259259.Ambient AmbientForceWallpaperSwap`, then relaunch. The status is "Live above the lock screen" again.

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientApp/Wallpaper Sources/AmbientApp/Settings/Panes/WallpaperPane.swift
git commit -m "feat(app): lock-screen fallback swaps the wallpaper while locked and restores it"
```

---

### Task 8: Harbor and Garden

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/HarborScene.swift`
- Create: `Sources/AmbientApp/Wallpaper/GardenScene.swift`
- Modify: `Sources/AmbientApp/Wallpaper/SceneRenderer.swift` (the registry)

**Interfaces:**
- Consumes: `SceneRenderer`, `SceneMotion`, `SceneRandom`, `GraphicsContext.fillGlow/fillCircle/fillVertical`, `glowLevel`, `scenePoint`, `arrivalProgress` (Task 4); `SceneState`, `DayLight`, `DayPhase`, `DayMark` (Tasks 1–2).
- Produces: `struct HarborScene: SceneRenderer`, `struct GardenScene: SceneRenderer`; `SceneRenderers.renderer(for:)` returns each kind's own renderer.

- [ ] **Step 1: Create Harbor**

Create `Sources/AmbientApp/Wallpaper/HarborScene.swift`:

```swift
import AmbientCore
import SwiftUI

/// Every session is a boat, and its spot is the lantern at the top of its mast. Working boats sail with a wake,
/// one that needs you swings an amber lantern, and finished turns moor along the pier. A lighthouse sweeps the
/// water at night.
struct HarborScene: SceneRenderer {
    private static let deskSpots: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.64), CGPoint(x: 0.60, y: 0.60), CGPoint(x: 0.40, y: 0.70), CGPoint(x: 0.56, y: 0.74),
        CGPoint(x: 0.30, y: 0.64), CGPoint(x: 0.66, y: 0.70), CGPoint(x: 0.20, y: 0.72), CGPoint(x: 0.46, y: 0.58),
        CGPoint(x: 0.78, y: 0.76), CGPoint(x: 0.34, y: 0.78), CGPoint(x: 0.12, y: 0.64), CGPoint(x: 0.88, y: 0.72),
    ]
    /// Clear of the lock screen's clock (top center) and password field (bottom center).
    private static let lockSpots: [CGPoint] = [
        CGPoint(x: 0.26, y: 0.62), CGPoint(x: 0.66, y: 0.76), CGPoint(x: 0.18, y: 0.70), CGPoint(x: 0.90, y: 0.76),
        CGPoint(x: 0.32, y: 0.72), CGPoint(x: 0.12, y: 0.62), CGPoint(x: 0.76, y: 0.82), CGPoint(x: 0.24, y: 0.80),
        CGPoint(x: 0.36, y: 0.60), CGPoint(x: 0.64, y: 0.60), CGPoint(x: 0.08, y: 0.76), CGPoint(x: 0.84, y: 0.84),
    ]

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let spots = surface == .desk ? Self.deskSpots : Self.lockSpots
        return spots[((slot % spots.count) + spots.count) % spots.count]
    }

    private struct Look {
        let top, middle, horizon, seaTop, seaBottom, sun, shore: RGB
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night:
            Look(top: RGB(hex: "#03050F"), middle: RGB(hex: "#0C1330"), horizon: RGB(hex: "#1C2350"),
                 seaTop: RGB(hex: "#141A38"), seaBottom: RGB(hex: "#05070F"), sun: RGB(hex: "#C8D2FF"), shore: RGB(hex: "#0B0C1C"))
        case .dawn:
            Look(top: RGB(hex: "#25306A"), middle: RGB(hex: "#6B5A8C"), horizon: RGB(hex: "#F0B48E"),
                 seaTop: RGB(hex: "#6B5F86"), seaBottom: RGB(hex: "#1A1C36"), sun: RGB(hex: "#FFD9A8"), shore: RGB(hex: "#2A2745"))
        case .day:
            Look(top: RGB(hex: "#3A7FD6"), middle: RGB(hex: "#6AAAE8"), horizon: RGB(hex: "#C2E3F8"),
                 seaTop: RGB(hex: "#3F86C4"), seaBottom: RGB(hex: "#1D4E7A"), sun: RGB(hex: "#FFFFFF"), shore: RGB(hex: "#3F6A55"))
        case .dusk:
            Look(top: RGB(hex: "#0C1230"), middle: RGB(hex: "#2A2A5C"), horizon: RGB(hex: "#F19A60"),
                 seaTop: RGB(hex: "#4A3558"), seaBottom: RGB(hex: "#080A17"), sun: RGB(hex: "#FFD39A"), shore: RGB(hex: "#231A36"))
        }
    }

    /// Where the day's `index`th finished turn is moored: two rows of twenty along the pier, oldest first.
    private static func mooring(_ index: Int, size: CGSize) -> CGPoint {
        let row = index / 20, column = index % 20
        return CGPoint(x: size.width * CGFloat(0.735 + Double(column) * 0.0135),
                       y: size.height * CGFloat(row == 0 ? 0.69 : 0.645))
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let light = state.light
        let u = size.height / 1000
        let w = size.width, h = size.height
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }
        let night = light.amount { $0 == .night ? 1 : 0 }
        let hull = light.color { Self.look($0).shore }.mixed(with: RGB(r: 0, g: 0, b: 0), 0.45).color

        ctx.fillVertical(CGRect(origin: .zero, size: size),
                         [(0, mix(\.top)), (0.3, mix(\.middle)), (0.6, mix(\.horizon)), (1, mix(\.horizon))])

        // The sun low at dawn and dusk and high by day; the moon at night.
        let sun = CGPoint(x: w * CGFloat(light.amount { $0 == .night ? 0.78 : 0.29 }),
                          y: h * CGFloat(light.amount { $0 == .day ? 0.18 : ($0 == .night ? 0.16 : 0.6) }))
        let sunRadius = CGFloat(light.amount { $0 == .night ? 22 : 60 }) * u
        ctx.fillGlow(at: sun, radius: sunRadius * 4, color: mix(\.sun).opacity(light.amount { $0 == .day ? 0.35 : 0.8 }))
        ctx.fillCircle(at: sun, radius: sunRadius, color: mix(\.sun))

        // The sea hides the lower half of a setting sun.
        ctx.fillVertical(CGRect(x: 0, y: h * 0.6, width: w, height: h * 0.4),
                         [(0, mix(\.seaTop)), (0.35, mix(\.seaBottom)), (1, mix(\.seaBottom))])
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 18 * u))
            layer.fill(Path(ellipseIn: CGRect(x: sun.x - 36 * u, y: h * 0.6, width: 72 * u, height: h * 0.22)),
                       with: .color(mix(\.sun).opacity(0.25)))
        }
        waves(&ctx, size: size, u: u, t: t)
        shores(&ctx, size: size, color: mix(\.shore))
        lighthouse(&ctx, size: size, u: u, t: t, night: night, color: mix(\.shore))

        moored(&ctx, size: size, marks: state.marks, date: date, u: u, hull: hull)
        pier(&ctx, size: size, u: u, color: mix(\.shore))

        for inhabitant in state.inhabitants {
            boat(&ctx, inhabitant, lantern: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, t: t, date: date, motion: motion, hull: hull)
        }
    }

    private func waves(_ ctx: inout GraphicsContext, size: CGSize, u: CGFloat, t: TimeInterval) {
        var rng = SceneRandom(seed: 5)
        for _ in 0..<10 {
            let x = rng.next() * 0.9, y = 0.63 + rng.next() * 0.3, length = 0.04 + rng.next() * 0.06, phase = rng.next() * 6.3
            let drift = sin(t * 0.25 + phase) * 0.008
            var line = Path()
            line.move(to: CGPoint(x: size.width * CGFloat(x + drift), y: size.height * CGFloat(y)))
            line.addLine(to: CGPoint(x: size.width * CGFloat(x + drift + length), y: size.height * CGFloat(y)))
            ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 1.6 * u)
        }
    }

    private func shores(_ ctx: inout GraphicsContext, size: CGSize, color: Color) {
        let w = size.width, h = size.height
        var shore = Path()
        shore.move(to: CGPoint(x: 0, y: h * 0.6))
        shore.addCurve(to: CGPoint(x: w * 0.19, y: h * 0.6), control1: CGPoint(x: w * 0.06, y: h * 0.583),
                       control2: CGPoint(x: w * 0.13, y: h * 0.59))
        shore.closeSubpath()
        shore.move(to: CGPoint(x: w * 0.74, y: h * 0.6))
        shore.addCurve(to: CGPoint(x: w, y: h * 0.585), control1: CGPoint(x: w * 0.82, y: h * 0.57),
                       control2: CGPoint(x: w * 0.92, y: h * 0.572))
        shore.addLine(to: CGPoint(x: w, y: h * 0.6))
        shore.closeSubpath()
        ctx.fill(shore, with: .color(color))
    }

    private func lighthouse(_ ctx: inout GraphicsContext, size: CGSize, u: CGFloat, t: TimeInterval, night: Double, color: Color) {
        let lamp = CGPoint(x: size.width * 0.05, y: size.height * 0.585 - 38 * u)
        ctx.fill(Path(CGRect(x: lamp.x - 5 * u, y: lamp.y, width: 10 * u, height: 38 * u)), with: .color(color))
        guard night > 0.01 else { return }
        let beamColor = Color(red: 1, green: 0.93, blue: 0.7)
        let angle = t == 0 ? 0.25 : sin(t * 0.35) * 0.35 + 0.2
        let reach = size.width * 0.55
        var beam = Path()
        beam.move(to: lamp)
        beam.addLine(to: CGPoint(x: lamp.x + reach * CGFloat(cos(angle - 0.05)), y: lamp.y + reach * CGFloat(sin(angle - 0.05))))
        beam.addLine(to: CGPoint(x: lamp.x + reach * CGFloat(cos(angle + 0.05)), y: lamp.y + reach * CGFloat(sin(angle + 0.05))))
        beam.closeSubpath()
        ctx.fill(beam, with: .linearGradient(Gradient(colors: [beamColor.opacity(0.28 * night), beamColor.opacity(0)]),
                                             startPoint: lamp, endPoint: CGPoint(x: lamp.x + reach, y: lamp.y)))
        ctx.fillGlow(at: lamp, radius: 26 * u, color: beamColor.opacity(night))
    }

    private func pier(_ ctx: inout GraphicsContext, size: CGSize, u: CGFloat, color: Color) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(x: w * 0.72, y: h * 0.66, width: w * 0.28, height: 10 * u)), with: .color(color))
        for k in 0..<5 {
            let x = w * CGFloat(0.73 + Double(k) * 0.065)
            ctx.fill(Path(CGRect(x: x, y: h * 0.66, width: 6 * u, height: 50 * u)), with: .color(color))
        }
    }

    private func moored(_ ctx: inout GraphicsContext, size: CGSize, marks: [DayMark], date: Date, u: CGFloat, hull: Color) {
        for (i, mark) in marks.enumerated() {
            var p = Self.mooring(i, size: size)
            // The newest one glides in to its place.
            if i == marks.count - 1, let f = arrivalProgress(of: marks, at: date) { p.x -= 160 * u * CGFloat(1 - f) }
            ctx.fill(hullPath(deck: p, scale: 0.28 * u), with: .color(hull))
            let color = mark.outcome == .failed ? Palette.error : Palette.agent(mark.agent)
            ctx.fillCircle(at: CGPoint(x: p.x, y: p.y - 8 * u), radius: 2.5 * u, color: color.color)
        }
    }

    private func boat(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, lantern spot: CGPoint, u: CGFloat,
                      t: TimeInterval, date: Date, motion: SceneMotion, hull: Color) {
        let s = 0.55 * u
        let deck = CGPoint(x: spot.x, y: spot.y + 134 * s)
        let body = Palette.agent(inhabitant.agent).color
        let glow = Palette.mood(inhabitant.mood, agent: inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)

        if inhabitant.mood == .working {
            // A wake that lengthens as the turn does more.
            let length = CGFloat(60 + 160 * inhabitant.busyness) * u
            for (k, offset) in [CGFloat(0), 12].enumerated() {
                var wake = Path()
                wake.move(to: CGPoint(x: deck.x - 60 * s, y: deck.y + (14 + offset) * s))
                wake.addLine(to: CGPoint(x: deck.x - 60 * s - length, y: deck.y + (20 + offset) * s))
                ctx.stroke(wake, with: .color(.white.opacity(k == 0 ? 0.35 : 0.2)),
                           style: StrokeStyle(lineWidth: 2 * u, dash: [10 * u, 10 * u], dashPhase: CGFloat(-t * 18)))
            }
        }
        ctx.fill(hullPath(deck: deck, scale: s), with: .color(hull))
        var stripe = Path()
        stripe.move(to: CGPoint(x: deck.x - 58 * s, y: deck.y + 3 * s))
        stripe.addLine(to: CGPoint(x: deck.x + 58 * s, y: deck.y + 3 * s))
        ctx.stroke(stripe, with: .color(body), lineWidth: 3 * s)
        var mast = Path()
        mast.move(to: deck)
        mast.addLine(to: CGPoint(x: deck.x, y: spot.y + 4 * s))
        ctx.stroke(mast, with: .color(hull), lineWidth: 3 * s)
        if inhabitant.mood == .working {
            var sail = Path()
            sail.move(to: CGPoint(x: deck.x + 4 * s, y: spot.y + 10 * s))
            sail.addLine(to: CGPoint(x: deck.x + 58 * s, y: deck.y - 6 * s))
            sail.addLine(to: CGPoint(x: deck.x + 4 * s, y: deck.y - 6 * s))
            sail.closeSubpath()
            ctx.fill(sail, with: .color(hull.opacity(0.85)))
        }

        // The lantern: swings when it needs you, fires a flare when it failed, dark when idle.
        var lamp = spot
        if inhabitant.mood == .waiting { lamp.x += CGFloat(sin(t * 2.2)) * 5 * u }
        guard inhabitant.mood != .idle else {
            ctx.fillCircle(at: lamp, radius: 3 * u, color: .white.opacity(0.35))
            return
        }
        ctx.fillGlow(at: lamp, radius: 80 * u, color: glow.opacity(level))
        ctx.fillCircle(at: lamp, radius: 4.5 * u, color: .white.opacity(0.95))
        if inhabitant.mood == .error, t != 0 {
            let rise = t.truncatingRemainder(dividingBy: 2) / 2
            let flare = CGPoint(x: lamp.x, y: lamp.y - CGFloat(rise) * 90 * u)
            ctx.fillGlow(at: flare, radius: 30 * u, color: Palette.error.color.opacity(1 - rise))
        }
    }

    private func hullPath(deck: CGPoint, scale s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: deck.x - 60 * s, y: deck.y))
        p.addLine(to: CGPoint(x: deck.x + 60 * s, y: deck.y))
        p.addLine(to: CGPoint(x: deck.x + 43 * s, y: deck.y + 26 * s))
        p.addLine(to: CGPoint(x: deck.x - 43 * s, y: deck.y + 26 * s))
        p.closeSubpath()
        return p
    }
}
```

- [ ] **Step 2: Create Garden**

Create `Sources/AmbientApp/Wallpaper/GardenScene.swift`:

```swift
import AmbientCore
import SwiftUI

/// Every session is a plant, and its spot is the plant's head. A working plant grows taller as its turn does more;
/// one that needs you holds up a glowing bud, a finished one blooms, a failed one droops. Finished turns leave
/// small flowers in the bed. Fireflies come out at night.
struct GardenScene: SceneRenderer {
    private static let deskSpots: [CGPoint] = [
        CGPoint(x: 0.63, y: 0.56), CGPoint(x: 0.74, y: 0.64), CGPoint(x: 0.52, y: 0.66), CGPoint(x: 0.84, y: 0.58),
        CGPoint(x: 0.44, y: 0.60), CGPoint(x: 0.58, y: 0.72), CGPoint(x: 0.92, y: 0.66), CGPoint(x: 0.36, y: 0.68),
        CGPoint(x: 0.68, y: 0.50), CGPoint(x: 0.80, y: 0.72), CGPoint(x: 0.28, y: 0.62), CGPoint(x: 0.48, y: 0.52),
    ]
    /// Clear of the lock screen's clock (top center) and password field (bottom center).
    private static let lockSpots: [CGPoint] = [
        CGPoint(x: 0.70, y: 0.58), CGPoint(x: 0.80, y: 0.66), CGPoint(x: 0.28, y: 0.60), CGPoint(x: 0.20, y: 0.68),
        CGPoint(x: 0.86, y: 0.56), CGPoint(x: 0.66, y: 0.68), CGPoint(x: 0.34, y: 0.66), CGPoint(x: 0.14, y: 0.58),
        CGPoint(x: 0.74, y: 0.50), CGPoint(x: 0.92, y: 0.64), CGPoint(x: 0.24, y: 0.52), CGPoint(x: 0.10, y: 0.66),
    ]

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let spots = surface == .desk ? Self.deskSpots : Self.lockSpots
        return spots[((slot % spots.count) + spots.count) % spots.count]
    }

    private struct Look {
        let top, middle, horizon, hills, groundTop, groundBottom: RGB
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night:
            Look(top: RGB(hex: "#050817"), middle: RGB(hex: "#10163A"), horizon: RGB(hex: "#1C2250"),
                 hills: RGB(hex: "#14142C"), groundTop: RGB(hex: "#0D1614"), groundBottom: RGB(hex: "#050807"))
        case .dawn:
            Look(top: RGB(hex: "#2A2F5E"), middle: RGB(hex: "#7A5C88"), horizon: RGB(hex: "#EAB18C"),
                 hills: RGB(hex: "#3A3358"), groundTop: RGB(hex: "#24302C"), groundBottom: RGB(hex: "#0E1512"))
        case .day:
            Look(top: RGB(hex: "#4E97E0"), middle: RGB(hex: "#86C0EE"), horizon: RGB(hex: "#CFEAF8"),
                 hills: RGB(hex: "#5F8A6A"), groundTop: RGB(hex: "#3D6B43"), groundBottom: RGB(hex: "#1F3A24"))
        case .dusk:
            Look(top: RGB(hex: "#0D1331"), middle: RGB(hex: "#352D62"), horizon: RGB(hex: "#F0AE78"),
                 hills: RGB(hex: "#2A2446"), groundTop: RGB(hex: "#1B2A2A"), groundBottom: RGB(hex: "#070D0C"))
        }
    }

    private static func fireflies(_ phase: DayPhase) -> Double {
        switch phase {
        case .night: 1
        case .dusk: 0.6
        case .dawn: 0.1
        case .day: 0
        }
    }

    /// Where the day's `index`th finished turn blooms: two rows of twenty in the bed, oldest first.
    private static func bedPoint(_ index: Int, size: CGSize) -> CGPoint {
        let row = index / 20, column = index % 20
        return CGPoint(x: size.width * CGFloat(0.10 + Double(column) * 0.016 + Double(row) * 0.008),
                       y: size.height * CGFloat(0.885 + Double(row) * 0.022))
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let light = state.light
        let u = size.height / 1000
        let w = size.width, h = size.height
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }

        ctx.fillVertical(CGRect(origin: .zero, size: size),
                         [(0, mix(\.top)), (0.34, mix(\.middle)), (0.6, mix(\.horizon)), (1, mix(\.horizon))])

        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: h * 0.61))
        hills.addCurve(to: CGPoint(x: w * 0.40, y: h * 0.57), control1: CGPoint(x: w * 0.12, y: h * 0.56),
                       control2: CGPoint(x: w * 0.26, y: h * 0.59))
        hills.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.575), control1: CGPoint(x: w * 0.55, y: h * 0.55),
                       control2: CGPoint(x: w * 0.66, y: h * 0.54))
        hills.addCurve(to: CGPoint(x: w, y: h * 0.57), control1: CGPoint(x: w * 0.88, y: h * 0.60),
                       control2: CGPoint(x: w * 0.95, y: h * 0.59))
        hills.addLine(to: CGPoint(x: w, y: h))
        hills.addLine(to: CGPoint(x: 0, y: h))
        hills.closeSubpath()
        ctx.fill(hills, with: .color(mix(\.hills)))

        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.66))
        ground.addCurve(to: CGPoint(x: w, y: h * 0.65), control1: CGPoint(x: w * 0.3, y: h * 0.64),
                        control2: CGPoint(x: w * 0.7, y: h * 0.655))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        ctx.fill(ground, with: .linearGradient(Gradient(colors: [mix(\.groundTop), mix(\.groundBottom)]),
                                               startPoint: CGPoint(x: 0, y: h * 0.65), endPoint: CGPoint(x: 0, y: h)))

        grass(&ctx, size: size, u: u, color: mix(\.groundBottom))
        bed(&ctx, size: size, marks: state.marks, date: date, u: u)
        for inhabitant in state.inhabitants {
            plant(&ctx, inhabitant, head: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                  size: size, u: u, date: date, motion: motion)
        }
        let glow = light.amount(Self.fireflies)
        if glow > 0.01 { fireflies(&ctx, size: size, amount: glow, u: u, date: date, motion: motion) }
    }

    private func grass(_ ctx: inout GraphicsContext, size: CGSize, u: CGFloat, color: Color) {
        var rng = SceneRandom(seed: 3)
        for _ in 0..<60 {
            let x = size.width * CGFloat(rng.next())
            let base = size.height * CGFloat(0.93 + rng.next() * 0.07)
            let height = CGFloat(30 + rng.next() * 40) * u
            let lean = CGFloat(rng.next() - 0.5) * 20 * u
            var blade = Path()
            blade.move(to: CGPoint(x: x, y: base))
            blade.addQuadCurve(to: CGPoint(x: x + lean, y: base - height), control: CGPoint(x: x + lean / 3, y: base - height / 2))
            ctx.stroke(blade, with: .color(color), style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round))
        }
    }

    private func bed(_ ctx: inout GraphicsContext, size: CGSize, marks: [DayMark], date: Date, u: CGFloat) {
        for (i, mark) in marks.enumerated() {
            let p = Self.bedPoint(i, size: size)
            // The newest one opens as it arrives.
            var grow: CGFloat = 1
            if i == marks.count - 1, let f = arrivalProgress(of: marks, at: date) { grow = CGFloat(f) }
            let r = 5 * max(u, 0.5) * grow
            if mark.outcome == .failed {
                ctx.fillCircle(at: CGPoint(x: p.x, y: p.y + 2 * u), radius: r * 0.8, color: Palette.error.color.opacity(0.7))
            } else {
                ctx.fillCircle(at: p, radius: r, color: Palette.agent(mark.agent).color)
                ctx.fillCircle(at: p, radius: r * 0.4, color: Color(red: 1, green: 0.91, blue: 0.66))
            }
        }
    }

    private func plant(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, head spot: CGPoint, size: CGSize,
                       u: CGFloat, date: Date, motion: SceneMotion) {
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        let body = Palette.agent(inhabitant.agent).color
        let glow = Palette.mood(inhabitant.mood, agent: inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)
        let stemColor = Color(red: 0.07, green: 0.19, blue: 0.16)

        // A working plant grows toward its spot as its turn does more.
        let growth = inhabitant.mood == .working ? CGFloat(1 - inhabitant.busyness) * 0.08 : 0
        var head = CGPoint(x: spot.x, y: spot.y + size.height * growth)
        head.x += CGFloat(sin(t * 0.8 + Double(inhabitant.slot))) * 3 * u
        let base = CGPoint(x: spot.x + 8 * u, y: size.height * 1.02)
        let rise = base.y - head.y
        let droops = inhabitant.mood == .error
        let tip = droops ? CGPoint(x: head.x + 18 * u, y: head.y + 22 * u) : head

        var stem = Path()
        stem.move(to: base)
        stem.addCurve(to: tip, control1: CGPoint(x: base.x - 10 * u, y: base.y - rise * 0.4),
                      control2: droops ? CGPoint(x: head.x - 6 * u, y: head.y - 26 * u)
                                       : CGPoint(x: head.x + 6 * u, y: head.y + rise * 0.3))
        ctx.stroke(stem, with: .color(stemColor), style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
        leaf(&ctx, at: CGPoint(x: base.x - 4 * u, y: base.y - rise * 0.45), side: 1, u: u, color: stemColor)
        leaf(&ctx, at: CGPoint(x: base.x - 6 * u, y: base.y - rise * 0.7), side: -1, u: u, color: stemColor)

        switch inhabitant.mood {
        case .idle:
            ctx.fillCircle(at: tip, radius: 6 * u, color: body.opacity(0.45))
        case .working:
            ctx.fillGlow(at: tip, radius: CGFloat(60 + 30 * inhabitant.busyness) * u, color: glow.opacity(level))
            ctx.fillCircle(at: tip, radius: 6 * u, color: .white.opacity(0.9))
            ctx.fillCircle(at: tip, radius: 3 * u, color: body)
        case .waiting:
            ctx.fillGlow(at: tip, radius: 95 * u, color: glow.opacity(level))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 12 * u, y: tip.y - 18 * u, width: 24 * u, height: 36 * u)), with: .color(body))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 6 * u, y: tip.y - 14 * u, width: 12 * u, height: 20 * u)),
                     with: .color(Color(red: 1, green: 0.85, blue: 0.64).opacity(0.8)))
        case .done:
            ctx.fillGlow(at: tip, radius: 75 * u, color: glow.opacity(level))
            for k in 0..<5 {
                let angle = Double(k) * 2 * .pi / 5 - .pi / 2
                ctx.fillCircle(at: CGPoint(x: tip.x + CGFloat(cos(angle)) * 16 * u, y: tip.y + CGFloat(sin(angle)) * 16 * u),
                               radius: 11 * u, color: body)
            }
            ctx.fillCircle(at: tip, radius: 7 * u, color: Color(red: 1, green: 0.91, blue: 0.66))
        case .error:
            ctx.fillGlow(at: tip, radius: 60 * u, color: glow.opacity(level))
            ctx.fillCircle(at: tip, radius: 8 * u, color: body.opacity(0.8))
        }
    }

    private func leaf(_ ctx: inout GraphicsContext, at p: CGPoint, side: CGFloat, u: CGFloat, color: Color) {
        var leaf = Path()
        leaf.move(to: p)
        leaf.addQuadCurve(to: CGPoint(x: p.x + side * 44 * u, y: p.y - 36 * u), control: CGPoint(x: p.x + side * 38 * u, y: p.y - 6 * u))
        leaf.addQuadCurve(to: p, control: CGPoint(x: p.x + side * 10 * u, y: p.y - 34 * u))
        ctx.fill(leaf, with: .color(color.opacity(0.9)))
    }

    private func fireflies(_ ctx: inout GraphicsContext, size: CGSize, amount: Double, u: CGFloat, date: Date, motion: SceneMotion) {
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        let warm = Color(red: 1, green: 0.91, blue: 0.54)
        var rng = SceneRandom(seed: 11)
        for _ in 0..<16 {
            let x = rng.next(), y = 0.62 + rng.next() * 0.3, speed = 0.2 + rng.next() * 0.3, phase = rng.next() * 6.3
            let dx = CGFloat(sin(t * speed + phase)) * 18 * u
            let dy = CGFloat(cos(t * speed * 1.3 + phase)) * 14 * u
            let p = CGPoint(x: size.width * CGFloat(x) + dx, y: size.height * CGFloat(y) + dy)
            let flicker = motion.still ? 0.8 : 0.35 + 0.65 * max(0, sin(t * 1.7 + phase * 3))
            ctx.fillGlow(at: p, radius: 14 * u, color: warm.opacity(amount * flicker * 0.8))
            ctx.fillCircle(at: p, radius: 2.4 * u, color: Color(red: 1, green: 0.95, blue: 0.7).opacity(amount * flicker))
        }
    }
}
```

- [ ] **Step 3: Register them**

In `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`, replace the body of `SceneRenderers.renderer(for:)` with:

```swift
        switch kind {
        case .sky: SkyScene()
        case .harbor: HarborScene()
        case .garden: GardenScene()
        }
```

- [ ] **Step 4: Build and look at every world**

Run: `swift build && scripts/build-app.sh --run`

Then:
1. In Settings › Wallpaper, the four scene cards show Sky, Harbor and Garden, and "A new one each day" shows a slice of each.
2. Pick **Harbor** and run `~/.ambient/bin/ambient demo`, then hide your windows. Check:
   - boats sit on the water, with labels beside their lanterns;
   - the working boat has a sail and a moving wake;
   - needs-you swings an amber lantern;
   - finished turns moor along the pier;
   - no label overlaps the pier or the timeline.
3. Pick **Garden** and run the demo again. Check:
   - plants rise from the ground;
   - the working plant's tip glows in its agent color;
   - needs-you holds up an amber bud, done blooms, and failed droops red;
   - finished turns leave flowers in the bed above the story line.
4. To see the other phases without waiting: temporarily add `let light = DayLight(from: .night, to: .night, blend: 0)` as the first line of `draw` in each scene, rebuild, look at it, and remove it. Repeat with `.day`, and with `.dawn` blending into `.day`. By day the text turns dark and stays readable.
5. If a label collides with scenery at your display's size, adjust that scene's spot table (not the text layer) and rebuild.
6. With Reduce Motion on (System Settings › Accessibility › Display), wakes, sways, fireflies and sparks hold still, and glows still fade.

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientApp/Wallpaper
git commit -m "feat(app): Harbor and Garden scenes"
```

---

### Task 9: Your next calendar event

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/CalendarSource.swift`
- Modify: `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- Modify: `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- Modify: `Sources/AmbientApp/Settings/SettingsView.swift`
- Modify: `Resources/Info.plist`
- Modify: `Resources/Ambient.entitlements`

**Interfaces:**
- Consumes: `CalendarEvent` (Task 2), `SceneState.make(... nextEvent:)` (Task 2), `Preferences.wallpaperCalendar` (Task 4), the Task 7 coordinator and pane.
- Produces:
  - `final class CalendarSource: ObservableObject`:
    - `@Published private(set) var next: CalendarEvent?`, `hasAccess: Bool`, `canAsk: Bool`
    - `func start()`, `func stop()`, `func requestAccess()`, `func refresh()`
  - `LivingWallpaper.calendar`
  - `WallpaperPane(prefs:wallpaper:calendar:)`

- [ ] **Step 1: Create the calendar source**

Create `Sources/AmbientApp/Wallpaper/CalendarSource.swift`:

```swift
import AmbientCore
import EventKit
import Foundation

/// Your next timed event later today, from macOS Calendar. Optional: without access there is none.
final class CalendarSource: ObservableObject {
    @Published private(set) var next: CalendarEvent?
    @Published private(set) var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    /// Access hasn't been asked for yet, so asking shows the system prompt.
    @Published private(set) var canAsk = EKEventStore.authorizationStatus(for: .event) == .notDetermined

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if next != nil { next = nil }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess != (status == .fullAccess) { hasAccess = status == .fullAccess }
        if canAsk != (status == .notDetermined) { canAsk = status == .notDetermined }
        guard running, hasAccess else {
            if next != nil { next = nil }
            return
        }
        let now = Date()
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil))
        let upcoming = events.filter { !$0.isAllDay && $0.startDate > now }.min { $0.startDate < $1.startDate }
        let found = upcoming.map { CalendarEvent(title: $0.title ?? "Event", start: $0.startDate) }
        if found != next { next = found }
    }
}
```

- [ ] **Step 2: Feed the event into the scene**

In `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, make these four edits:

1. Below `let feed = SceneFeed()`, add:

```swift
    let calendar = CalendarSource()
```

2. In `start()`, immediately before the line `locked = lockMonitor.isLocked`, insert:

```swift
        calendar.$next
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
```

3. In `refresh()`, replace

```swift
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   keeping: slots)
```

with

```swift
        if prefs.wallpaperCalendar { calendar.start() } else { calendar.stop() }
        let next = prefs.wallpaperCalendar ? calendar.next : nil
        let desk = SceneState.make(sessions: model.sessions, day: model.day, now: now, kind: kind, surface: .desk,
                                   nextEvent: next, keeping: slots)
```

and replace

```swift
                              lockMessages: prefs.wallpaperLockMessages, keeping: slots)
```

with

```swift
                              lockMessages: prefs.wallpaperLockMessages, nextEvent: next, keeping: slots)
```

4. In `turnOff()`, after `lockLayer?.uninstall()`, add:

```swift
        calendar.stop()
```

- [ ] **Step 3: Add the calendar setting**

In `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`:
- add `@ObservedObject var calendar: CalendarSource` below `@ObservedObject var wallpaper: LivingWallpaper`;
- insert this section inside the `Group`, after the "Lock screen" section:

```swift
                SettingsSection(header: "Your day", footer: "Ambient reads only your next timed event today, on your Mac.") {
                    SettingsToggleRow(title: "Next calendar event", isOn: $prefs.wallpaperCalendar)
                    if prefs.wallpaperCalendar && !calendar.hasAccess {
                        SettingsDivider()
                        SettingsRow(title: "Calendar access",
                                    subtitle: calendar.canAsk ? nil : "Allow Ambient in System Settings › Privacy & Security › Calendars.",
                                    subtitleStatus: .warning) {
                            if calendar.canAsk {
                                Button("Grant access…") { calendar.requestAccess() }.buttonStyle(.pill)
                            } else {
                                StatusBadge("Not allowed", .warning)
                            }
                        }
                    }
                }
```

In `Sources/AmbientApp/Settings/SettingsView.swift`, change the pane case to:

```swift
            WallpaperPane(prefs: prefs, wallpaper: wallpaper, calendar: wallpaper.calendar)
```

- [ ] **Step 4: Declare the permission**

In `Resources/Info.plist`, add before `<key>NSHumanReadableCopyright</key>`:

```xml
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Ambient shows your next event today on its living wallpaper. Nothing leaves your Mac.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>Ambient shows your next event today on its living wallpaper. Nothing leaves your Mac.</string>
```

In `Resources/Ambient.entitlements`, add inside `<dict>`:

```xml
	<!-- Show your next event today on the living wallpaper. -->
	<key>com.apple.security.personal-information.calendars</key>
	<true/>
```

- [ ] **Step 5: Build and check**

Run: `swift build && scripts/build-app.sh --run && codesign -d --entitlements - build/Ambient.app 2>/dev/null | grep calendars`
Expected: the build succeeds and the entitlement is printed.

Then:
1. In Calendar, add an event later today, e.g. "Design review".
2. In Settings › Wallpaper, turn on **Next calendar event**, then click **Grant access…** and allow. Within a moment the desktop shows "Design review at HH:MM" under the date.
3. Lock (Ctrl-Cmd-Q). The lock screen shows "Next event at HH:MM", without the title. Turn on **Show messages on the lock screen** and the title appears there too.
4. Turn **Next calendar event** off. The line disappears from both.
5. Denied path: `tccutil reset Calendar com.viveky259259.Ambient`, relaunch, turn it on, and deny in the prompt. The row shows "Not allowed" and the System Settings hint.

- [ ] **Step 6: Commit**

```bash
git add Sources/AmbientApp/Wallpaper Sources/AmbientApp/Settings Resources/Info.plist Resources/Ambient.entitlements
git commit -m "feat(app): next calendar event on the living wallpaper"
```

---

### Task 10: Docs and a final pass

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: README**

In `README.md`:

1. After the **Dock glow** bullet (the one ending "up behind the Dock's glass itself."), add:

```markdown
- **Living wallpaper** — a sky, a harbor or a garden that follows the time of day, where each session lives
  as a star, a boat or a plant glowing in the color of what it's doing. Around them: today's story (agent
  time, tools, turns, how often they needed you), the latest moments, the clock and your next event. On the
  desktop, and on the lock screen while you're away. Off until you turn it on in Settings › Wallpaper.
```

2. In *What Ambient changes on your system*, change the `~/.ambient/` row to:

```markdown
| `~/.ambient/` | The socket, a link to the bundled CLI, config backups, saved session state, today's story for the living wallpaper |
```

   and add this row after it:

```markdown
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` | Only when the lock screen can't show the living wallpaper live: while the Mac is locked the scene is set as your wallpaper, and on unlock the store is put back from a backup in `~/.ambient/backups/` |
```

3. In *Privacy*, after the paragraph that ends "never read beyond that and never stored.", add:

```markdown
The living wallpaper keeps today's counts and a timeline of what happened, where and when, in
`~/.ambient/day.json` — never prompts, summaries or commands — and starts fresh at midnight. On the lock
screen it hides messages and event titles unless you turn them on. Its calendar line reads only your next
timed event today, and only after you allow Calendar access. To draw above the lock screen, Ambient uses a
private macOS window API; if a macOS update breaks it, Ambient falls back to the wallpaper swap above.
```

4. In *Troubleshooting*, before the **Uninstall** bullet, add:

```markdown
- **The living wallpaper isn't on the lock screen** — Settings › Wallpaper says whether it's live, shown as
  your wallpaper while locked, or not available on this Mac. If Ambient ever quits while the Mac is locked, it
  puts your wallpaper back the next time it opens; *Restore my wallpaper* shows in Settings until it has.
```

5. In the *Build from source* table, change the `Sources/AmbientApp` row's description to:
   "The app: socket server, island, notifications and chimes, menu bar, Dock glow, living wallpaper, setup".

- [ ] **Step 2: CHANGELOG**

In `CHANGELOG.md`, add above `## 0.2.1 — 2026-09-28`:

```markdown
## Unreleased

- **Living wallpaper**: a Sky, Harbor or Garden scene that follows the time of day, where each agent session
  lives as a star, a boat or a plant in the color of what it's doing, with today's story, the latest moments,
  the clock and your next calendar event. It shows at the desk and on the lock screen. Off by default: turn it
  on in Settings › Wallpaper.
```

- [ ] **Step 3: Final pass**

Run: `swift test && scripts/build-app.sh --run`
Expected: every suite passes, and the app launches.

Then walk the spec's manual checklist once more, end to end, on the built app:
- **At the desk:** every Space and display; click-through; pausing when covered (CPU near 0) and running when uncovered (under 2 %).
- **Lock screen, live** (with `ambient demo` running): no clock of ours; nothing on the clock or the password field; free text hidden.
- **Fallback:** forced with `AmbientForceWallpaperSwap`, then unlock restores the wallpaper; `kill -9` mid-lock, then relaunch restores it.
- **Comfort:** Reduce Motion and Low Power Mode (System Settings › Battery) both give still frames or gentle fades.
- **Midnight:** set the clock forward past midnight with automatic time off, or wait for it. The day's story resets and "A new one each day" changes world. Then set the clock back.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: living wallpaper"
```
