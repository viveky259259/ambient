import AmbientCore
import SwiftUI

/// The real pet on a patch of desktop, acting out each pose in turn with its bubble.
struct PetPreview: View {
    let enabled: Bool
    let species: PetSpecies

    @State private var step = 0
    @State private var reactions = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let poses: [PetPose] = [.working, .waiting, .done, .error, .sleeping]

    var body: some View {
        let pose = reduceMotion ? .waiting : Self.poses[step % Self.poses.count]
        let session = Self.session(pose)
        PreviewStage(enabled: enabled, alignment: .center) {
            VStack(spacing: 0) {
                Group {
                    if let session {
                        PetBubble(session: session, badge: nil)
                            .frame(width: PetViewModel.bubbleSize.width, height: PetViewModel.bubbleSize.height)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.72)))
                            .environment(\.colorScheme, .dark)
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: PetViewModel.bubbleSize.height)
                PetFigure(species: species, pose: pose, tint: session.map { Palette.agent($0.agent) } ?? Palette.idle,
                          reaction: PetPolicy.reaction(to: pose), reactionCount: reactions)
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the desktop pet")
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled else { return }
                step += 1
                reactions += 1
            }
        }
    }

    private static func session(_ pose: PetPose) -> Session? {
        let now = Date()
        var s = Session(agent: .claude, sessionId: "preview", at: now)
        s.cwd = "/preview/api-server"
        s.turnStartedAt = now.addingTimeInterval(-134)
        s.activitySince = now.addingTimeInterval(-12)
        switch pose {
        case .sleeping: return nil
        case .working: s.activity = .tool(name: "Bash", detail: "npm test")
        case .waiting: s.activity = .waiting(reason: "permission", message: "Bash: rm -rf build")
        case .done:
            s.activity = .done(summary: "All 42 tests pass.")
            s.turnEndedAt = now
        case .error:
            s.activity = .error(message: "Build failed")
            s.turnEndedAt = now
        }
        return s
    }
}
