import AmbientCore
import SwiftUI

/// The real island, hanging from a pretend menu bar, cycling through what it shows.
struct IslandPreview: View {
    let enabled: Bool
    let showsWorking: Bool

    @StateObject private var island = IslandViewModel(geometry: IslandPreview.geometry)
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static let geometry = IslandGeometry(screenFrame: .zero, hasNotch: true, notchWidth: 150,
                                                 notchHeight: 24, centerX: 0)

    private enum Scene { case working, waiting, done }

    var body: some View {
        PreviewStage(enabled: enabled) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(scheme == .dark ? 0.08 : 0.3))
                    .frame(height: Self.geometry.notchHeight)
                IslandView(model: island)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the notch island")
        .onAppear(perform: apply)
        .onChange(of: enabled) { apply() }
        .onChange(of: showsWorking) { apply() }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return apply() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                step += 1
                apply()
            }
        }
    }

    private var scenes: [Scene] { showsWorking ? [.working, .waiting, .done] : [.waiting, .done] }

    private func apply() {
        guard enabled else {
            island.sessions = []
            island.presentation = .hidden
            return
        }
        let scene = reduceMotion ? .waiting : scenes[step % scenes.count]
        let session = Self.session(scene)
        island.sessions = [session]
        island.presentation = scene == .working ? .collapsed : .bloom(session.id)
    }

    private static func session(_ scene: Scene) -> Session {
        let now = Date()
        var s = Session(agent: .claude, sessionId: "preview", at: now)
        s.cwd = "/preview/api-server"
        s.turnStartedAt = now.addingTimeInterval(-134)
        switch scene {
        case .working:
            s.activity = .tool(name: "Bash", detail: "npm test")
        case .waiting:
            s.activity = .waiting(reason: "permission", message: "Bash: rm -rf build")
        case .done:
            s.activity = .done(summary: "All 42 tests pass. Ready for review.")
            s.turnEndedAt = now
        }
        return s
    }
}
