@testable import AmbientApp
@testable import AmbientCore
import Foundation
import SwiftUI
import Testing

@Suite struct VoiceFormatTests {
    @Test(arguments: [(0.0, "0:00"), (7.9, "0:07"), (59.99, "0:59"), (60, "1:00"), (102, "1:42"), (725, "12:05"),
                      (3_600, "60:00"), (-3, "0:00")])
    func clock(seconds: Double, expected: String) {
        #expect(VoiceFormat.clock(seconds) == expected)
    }
}

@Suite struct SettingsPaneTests {
    @Test func everyPaneHasADistinctTitleAndSymbol() {
        let all = SettingsPane.allCases
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.symbol)).count == all.count)
        #expect(all.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func onlyPanesWithoutTabsHaveTheirOwnSubtitle() {
        for pane in SettingsPane.allCases {
            #expect((pane.subtitle != nil) == [.board, .alerts].contains(pane), "\(pane)")
        }
    }

    @Test func everyTabHasATitleAndSubtitle() {
        let tabs: [(String, String)] = AgentsTab.allCases.map { ($0.title, $0.subtitle) }
            + AppearanceTab.allCases.map { ($0.title, $0.subtitle) }
            + VoiceTab.allCases.map { ($0.title, $0.subtitle) }
            + GeneralTab.allCases.map { ($0.title, $0.subtitle) }
        #expect(tabs.allSatisfy { !$0.0.isEmpty && !$0.1.isEmpty })
        #expect(Set(tabs.map(\.1)).count == tabs.count)
    }

    @Test func sidebarOrderStartsAtWelcomeAndEndsAtGeneral() {
        #expect(SettingsPane.allCases == [.welcome, .agents, .board, .alerts, .appearance, .voice, .general])
    }

    @Test func performanceWindows() {
        #expect(PerformancePane.Window.hour.seconds == 3_600)
        #expect(PerformancePane.Window.day.seconds == 86_400)
        #expect(PerformancePane.Window.allCases.map(\.rawValue) == ["Last hour", "Last 24 hours"])
    }
}

@Suite struct MoodColorTests {
    @Test(arguments: [
        (Activity.idle, Mood.idle), (.thinking, .working), (.tool(name: "Bash", detail: nil), .working),
        (.compacting, .working), (.waiting(reason: "permission", message: nil), .waiting), (.done(summary: nil), .done),
        (.error(message: nil), .error),
    ])
    func rawMoodIgnoresAcknowledgement(activity: Activity, mood: Mood) {
        #expect(activity.rawMood == mood)
    }

    @Test func tintIsWhatItDoesMoodTintIsHowMuchItWantsYou() {
        let s = makeSession("a", agent: .codex, activity: .done(summary: nil), acknowledged: true)
        #expect(s.tint == Palette.mood(.done, agent: .codex))
        #expect(s.moodTint == Palette.mood(.idle, agent: .codex))
    }

    @Test func rgbConvertsToSRGB() {
        let rgb = RGB(hex: "#FF8000")
        let ns = rgb.nsColor
        #expect(abs(ns.redComponent - 1) < 0.001)
        #expect(abs(ns.greenComponent - rgb.g) < 0.001)
        #expect(abs(ns.blueComponent) < 0.001)
    }

    @Test func statusTextColorsAreDistinctAndOnlyNeutralIsSecondary() {
        let tinted: [Theme.Status] = [.success, .warning, .error]
        #expect(tinted.allSatisfy { $0.textColor != .secondary })
        #expect(Set(tinted.map { "\($0.textColor)" }).count == tinted.count)
        #expect(Theme.Status.neutral.textColor == .secondary)
        #expect(Theme.Status.success.color == Palette.done.color)
        #expect(Theme.Status.error.color == Palette.error.color)
    }
}

@Suite struct WallpaperPreviewTests {
    @Test(arguments: SceneKind.allCases)
    func previewStateHasThreeDemoSessions(kind: SceneKind) {
        let state = WallpaperPreview.state(kind, now: testNow)
        #expect(state.kind == kind)
        #expect(state.surface == .desk)
        #expect(state.inhabitants.count == 3)
        #expect(Set(state.inhabitants.map(\.mood)) == [.waiting, .working, .done])
    }

    @Test(arguments: SceneKind.allCases)
    func thumbnailsShowTheWorldAlone(kind: SceneKind) {
        let state = WallpaperPreview.scenery(kind)
        #expect(state.kind == kind)
        #expect(state.inhabitants.isEmpty)
    }

    @Test func darkLookIsHonoured() {
        let light = WallpaperPreview.state(.sky, now: testNow, look: .light)
        let dark = WallpaperPreview.state(.sky, now: testNow, look: .dark)
        #expect(light.light != dark.light)
    }
}
