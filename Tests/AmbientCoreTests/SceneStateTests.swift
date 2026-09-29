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
        // Short enough that a label never reaches past a quarter of the screen.
        #expect(inhabitant.place.count <= 36 + 3 + 24)
        #expect(inhabitant.place.hasPrefix(String(repeating: "T", count: 35) + "…"))
        #expect((inhabitant.detail?.count ?? 0) <= 56)
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
