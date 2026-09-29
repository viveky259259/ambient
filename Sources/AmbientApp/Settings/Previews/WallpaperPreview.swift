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
