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

    @Test func theLookCanFollowTheDayTheSystemOrStayPut() {
        let evening = at(19, 0), noon = at(12, 0)
        #expect(SceneLook.timeOfDay.light(at: evening, systemDark: false, calendar: utc) == DayLight.at(evening, calendar: utc))
        #expect(SceneLook.light.light(at: evening, systemDark: true, calendar: utc) == DayLight(from: .day, to: .day, blend: 0))
        #expect(SceneLook.dark.light(at: noon, systemDark: false, calendar: utc) == DayLight(from: .night, to: .night, blend: 0))
        #expect(SceneLook.system.light(at: noon, systemDark: true, calendar: utc).dominant == .night)
        #expect(SceneLook.system.light(at: evening, systemDark: false, calendar: utc).darkInk)
        #expect(SceneLook(rawValue: "timeOfDay") == .timeOfDay)
        #expect(SceneLook.allCases.map(\.displayName) == ["Follow the time of day", "Match macOS", "Always light", "Always dark"])
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
        let days = (0..<SceneKind.allCases.count).map {
            ScenePolicy.kind(for: .daily, on: at(0, 1).addingTimeInterval(Double($0) * 86_400), calendar: utc)
        }
        #expect(Set(days) == Set(SceneKind.allCases))
        #expect(SceneKind.allCases.contains(.solar))
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
