import Foundation
import Testing
@testable import AmbientCore

private let t0 = Date(timeIntervalSince1970: 2_000_000)

private func session(_ id: String, _ activity: Activity, agent: AgentKind = .claude, seen: Bool = false) -> Session {
    var s = Session(agent: agent, sessionId: id, at: t0)
    s.activity = activity
    s.acknowledged = seen
    return s
}

private let working = Activity.tool(name: "Bash", detail: "npm test")
private let waiting = Activity.waiting(reason: "permission", message: "Bash: rm -rf build")

@Suite struct PetPolicyTests {
    @Test func idleAndSeenSessionsAreNotRelevant() {
        let sessions = [
            session("a", .idle),
            session("b", .done(summary: nil), seen: true),
            session("c", .error(message: nil), seen: true),
            session("d", working),
        ]
        #expect(PetPolicy.relevant(sessions).map(\.sessionId) == ["d"])
    }

    @Test func relevantKeepsTheStoresUrgencyOrder() {
        let sessions = [session("w", waiting), session("e", .error(message: nil)), session("k", working)]
        #expect(PetPolicy.relevant(sessions).map(\.sessionId) == ["w", "e", "k"])
    }

    @Test func petSleepsWithNothingRelevant() {
        #expect(PetPolicy.pose([]) == .sleeping)
        #expect(PetPolicy.pose([session("a", .idle)]) == .sleeping)
    }

    @Test func poseFollowsTheMostUrgentSession() {
        #expect(PetPolicy.pose([session("k", working)]) == .working)
        #expect(PetPolicy.pose([session("w", waiting), session("k", working)]) == .waiting)
        #expect(PetPolicy.pose([session("d", .done(summary: nil))]) == .done)
        #expect(PetPolicy.pose([session("e", .error(message: nil))]) == .error)
    }

    @Test func aSeenPromptIsWorkingAgain() {
        #expect(PetPolicy.pose([session("w", waiting, seen: true)]) == .working)
    }

    @Test func everyPoseHasItsOwnReaction() {
        let reactions = PetPose.allCases.map(PetPolicy.reaction(to:))
        #expect(Set(reactions).count == PetPose.allCases.count)
        #expect(PetPolicy.reaction(to: .sleeping) == .wake)
        #expect(PetPolicy.reaction(to: .done) == .cheer)
        #expect(PetPolicy.reaction(to: .error) == .shake)
    }

    @Test func listIsCappedWithACountOfTheRest() {
        let sessions = (0..<8).map { session("s\($0)", working) }
        let list = PetPolicy.listed(sessions)
        #expect(list.shown.count == PetPolicy.maxListed)
        #expect(list.more == 3)
    }

    @Test func unpromptedReactionsOnlyForTheMomentsTheIslandBloomsFor() {
        let store = SessionStore()
        func apply(_ kind: EventKind) -> SessionChange {
            store.apply(AgentEvent(agent: .claude, sessionId: "s", cwd: "/p", kind: kind, timestamp: t0))!
        }
        #expect(PetPolicy.announce(apply(.promptSubmitted), quiet: false) == nil)
        #expect(PetPolicy.announce(apply(.needsInput(reason: "permission", message: nil)), quiet: false) == .wave)
        #expect(PetPolicy.announce(apply(.turnFailed(message: nil)), quiet: true) == nil)
    }
}

@Suite struct PetArtTests {
    private static let palette: Set<Character> = Set(".obshwekgaGcz")

    @Test func everySpeciesHasTwoFramesOfTheSameSize() {
        for species in PetSpecies.allCases {
            let frames = PetArt.frames(species)
            #expect(frames.count == 2)
            for f in frames {
                #expect(f.body.width == PetArt.bodySize.width, "\(species)")
                #expect(f.body.height == PetArt.bodySize.height, "\(species)")
            }
        }
    }

    @Test func spritesAreRectangularAndUseKnownColors() {
        var sprites = PetSpecies.allCases.flatMap { PetArt.frames($0).map(\.body) }
        sprites += PetExpression.allCases.map(PetArt.eye)
        sprites += PetProp.allCases.map(PetArt.prop)
        for sprite in sprites {
            #expect(sprite.rows.allSatisfy { $0.count == sprite.width })
            #expect(sprite.rows.joined().allSatisfy { Self.palette.contains($0) })
        }
    }

    @Test func eyesSitOnTheBody() {
        for species in PetSpecies.allCases {
            for frame in PetArt.frames(species) {
                #expect(frame.eyes.count == 2)
                for eye in frame.eyes {
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            let c = frame.body.pixel(x: eye.x + dx, y: eye.y + dy)
                            #expect(c == "b" || c == "h" || c == "s", "\(species) eye at \(eye)")
                        }
                    }
                }
            }
        }
    }

    @Test func mouthsSitOnTheBody() {
        for species in PetSpecies.allCases {
            for frame in PetArt.frames(species) {
                for pose in PetPose.allCases {
                    guard let mouth = PetArt.mouth(for: pose) else { continue }
                    for dy in 0..<mouth.height {
                        for dx in 0..<mouth.width {
                            let c = frame.body.pixel(x: frame.mouth.x + dx, y: frame.mouth.y + dy)
                            #expect(c == "b" || c == "s" || c == "w", "\(species) \(pose) mouth")
                        }
                    }
                }
            }
        }
    }

    @Test func doneAndFailedLookDifferentFromAsleep() {
        // Mood is never color alone: the face changes too.
        #expect(PetArt.mouth(for: .sleeping) == nil)
        #expect(PetArt.mouth(for: .done) != nil)
        #expect(PetArt.mouth(for: .error) != nil)
        #expect(PetArt.mouth(for: .done) != PetArt.mouth(for: .error))
    }

    @Test func pixelsOutsideTheSpriteAreTransparent() {
        let body = PetArt.frames(.blob)[0].body
        #expect(body.pixel(x: -1, y: 0) == nil)
        #expect(body.pixel(x: 0, y: body.height) == nil)
        #expect(body.pixel(x: 0, y: 0) == nil) // '.' is transparent
    }

    @Test func propsFitInTheCanvas() {
        for pose in PetPose.allCases {
            for frame in 0..<2 {
                for waiting in 0...12 {
                    for placed in PetArt.props(for: pose, frame: frame, waiting: waiting) {
                        let sprite = placed.sprite
                        #expect(placed.at.x >= 0 && placed.at.x + sprite.width <= PetArt.canvasSize.width, "\(pose)")
                        #expect(placed.at.y >= 0 && placed.at.y + sprite.height <= PetArt.canvasSize.height, "\(pose)")
                    }
                }
            }
        }
    }

    @Test func severalWaitingShowsTheirCountInsteadOfTheBang() {
        let one = PetArt.props(for: .waiting, frame: 0, waiting: 1).map(\.sprite)
        #expect(one == [PetArt.prop(.bang)])
        let three = PetArt.props(for: .waiting, frame: 0, waiting: 3).map(\.sprite)
        #expect(three == [PetArt.digit(3)])
        // Past nine, it stays at nine.
        #expect(PetArt.props(for: .waiting, frame: 0, waiting: 14).map(\.sprite) == [PetArt.digit(9)])
    }

    @Test func digitsAreDistinctAmberSprites() {
        let digits = (2...9).map(PetArt.digit)
        #expect(Set(digits.map(\.rows)).count == digits.count)
        for d in digits {
            #expect(d.rows.allSatisfy { $0.count == d.width })
            #expect(d.rows.joined().allSatisfy { $0 == "a" || $0 == "." })
        }
    }

    @Test func speciesRoundTripsThroughItsStoredName() {
        for species in PetSpecies.allCases { #expect(PetSpecies(rawValue: species.rawValue) == species) }
        #expect(PetSpecies(stored: "unicorn") == .blob)
    }
}

@Suite struct PetLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let pet = CGSize(width: 80, height: 72)
    private let panel = CGSize(width: 300, height: 400)

    @Test func defaultSpotIsTheBottomRightCorner() {
        let origin = PetLayout.defaultOrigin(in: screen, pet: pet)
        #expect(origin == CGPoint(x: 1440 - 80 - PetLayout.inset, y: PetLayout.inset))
    }

    @Test func petIsKeptOnScreen() {
        #expect(PetLayout.clamp(CGPoint(x: -50, y: 2000), pet: pet, in: screen) == CGPoint(x: 0, y: 900 - 72))
        #expect(PetLayout.clamp(CGPoint(x: 100, y: 100), pet: pet, in: screen) == CGPoint(x: 100, y: 100))
    }

    @Test func opensUpInTheLowerHalfAndDownInTheUpperHalf() {
        let low = PetLayout.place(pet: CGPoint(x: 600, y: 40), petSize: pet, panel: panel, in: screen)
        #expect(low.opensUp)
        #expect(low.panel.minY == 40)
        let high = PetLayout.place(pet: CGPoint(x: 600, y: 800), petSize: pet, panel: panel, in: screen)
        #expect(!high.opensUp)
        #expect(high.panel.maxY == 872)
    }

    @Test func panelCentersOnThePetAwayFromEdges() {
        let p = PetLayout.place(pet: CGPoint(x: 600, y: 40), petSize: pet, panel: panel, in: screen)
        #expect(p.panel.midX == 640)
        #expect(p.petInPanel == CGPoint(x: 110, y: 0))
    }

    @Test func panelStaysOnScreenAtTheEdge() {
        let p = PetLayout.place(pet: CGPoint(x: 1440 - 80, y: 40), petSize: pet, panel: panel, in: screen)
        #expect(p.panel.maxX == 1440)
        #expect(p.petInPanel.x == 220) // against the right edge of the panel
    }

    @Test func bubbleCentersOnThePetButStaysInThePanel() {
        #expect(PetLayout.bubbleCenterX(petMidX: 150, width: 200, panelWidth: 300) == 150)
        #expect(PetLayout.bubbleCenterX(petMidX: 260, width: 200, panelWidth: 300) == 196)
        #expect(PetLayout.bubbleCenterX(petMidX: 10, width: 200, panelWidth: 300) == 104)
    }
}

@Suite struct PetBurstTests {
    @Test func sameSeedSameParticles() {
        #expect(PetBurst.particles(seed: 7) == PetBurst.particles(seed: 7))
        #expect(PetBurst.particles(seed: 7) != PetBurst.particles(seed: 8))
    }

    @Test func particlesStartAtTheOriginAndFlyOut() {
        for p in PetBurst.particles(seed: 3) {
            #expect(p.offset(at: 0) == .zero)
            let later = p.offset(at: 0.2)
            #expect(hypot(later.x, later.y) > 5)
        }
    }

    @Test func particlesFadeOutByTheEnd() {
        for p in PetBurst.particles(seed: 3) {
            #expect(p.opacity(at: 0) == 1)
            #expect(p.opacity(at: PetBurst.lifetime) == 0)
            #expect(p.opacity(at: PetBurst.lifetime + 1) == 0)
        }
    }

    @Test func gravityPullsParticlesDownOverTime() {
        // Screen-down is +y in the view's coordinates.
        let p = PetBurst.Particle(angle: 0, speed: 100, size: 4, accent: false)
        #expect(p.offset(at: 0.6).y > p.offset(at: 0.2).y)
    }
}

private func titled(_ id: String, _ activity: Activity, title: String? = nil, agent: AgentKind = .claude) -> Session {
    var s = session(id, activity, agent: agent)
    s.title = title ?? id
    return s
}

@Suite struct PetMultiSessionTests {
    @Test func bubbleKeepsItsSessionWhileOthersOfTheSameUrgencyChurn() {
        // Two working sessions take turns being the most recent; the bubble shouldn't flip between them.
        let a = titled("a", working), b = titled("b", working)
        #expect(PetPolicy.primary([b, a], current: a.id)?.id == a.id)
        #expect(PetPolicy.primary([a, b], current: a.id)?.id == a.id)
    }

    @Test func bubbleSwitchesWhenSomethingMoreUrgentArrives() {
        let a = titled("a", working), b = titled("b", waiting)
        #expect(PetPolicy.primary([b, a], current: a.id)?.id == b.id)
    }

    @Test func bubbleMovesOnWhenItsSessionStopsMattering() {
        let a = titled("a", .idle), b = titled("b", working)
        #expect(PetPolicy.primary([b, a], current: a.id)?.id == b.id)
        #expect(PetPolicy.primary([b], current: "claude:gone")?.id == b.id)
        #expect(PetPolicy.primary([b], current: nil)?.id == b.id)
        #expect(PetPolicy.primary([a], current: a.id) == nil)
    }

    @Test func orderIsStableByUrgencyThenTitle() {
        // Store order (by recency) changes with every event; the pet's order doesn't.
        let s = [titled("z", working), titled("w", waiting), titled("a", working), titled("d", .done(summary: nil)),
                 titled("i", .idle)]
        #expect(PetPolicy.ordered(s).map(\.sessionId) == ["w", "d", "a", "z"])
        #expect(PetPolicy.ordered(s.reversed()).map(\.sessionId) == ["w", "d", "a", "z"])
    }

    @Test func badgeSaysWhenOthersNeedYou() {
        let p = titled("p", waiting)
        #expect(PetPolicy.badge([p, titled("q", waiting), titled("k", working)], primary: p.id) == "+1 needs you")
        #expect(PetPolicy.badge([p, titled("k", working), titled("l", working)], primary: p.id) == "+2")
        #expect(PetPolicy.badge([p, titled("i", .idle)], primary: p.id) == nil)
    }

    @Test func waitingCountsOnlyUnseenPrompts() {
        var seen = titled("s", waiting)
        seen.acknowledged = true
        #expect(PetPolicy.waitingCount([titled("a", waiting), titled("b", waiting), seen, titled("k", working)]) == 2)
    }

    @Test func summaryCountsEachMoodOnlyWithSeveralSessions() {
        let s = [titled("a", waiting), titled("b", waiting), titled("c", .done(summary: nil)),
                 titled("d", .error(message: nil)), titled("e", working), titled("f", working), titled("g", .idle)]
        #expect(PetPolicy.summary(s) == "Needs you 2 · Failed 1 · Done 1 · Working 2")
        #expect(PetPolicy.summary([titled("a", waiting), titled("e", working)]) == "Needs you 1 · Working 1")
        #expect(PetPolicy.summary([titled("a", waiting)]) == nil)
    }

    @Test func peekShowsEverySessionInUrgencyOrder() {
        let s = [titled("e", working), titled("a", waiting), titled("c", .done(summary: nil)), titled("i", .idle)]
        let peek = PetPolicy.peek(s)
        #expect(peek.shown.map(\.sessionId) == ["a", "c", "e"])
        #expect(peek.more == 0)
        let many = (0..<11).map { titled("w\($0)", working) }
        #expect(PetPolicy.peek(many).shown.count == PetPolicy.maxPeeked)
        #expect(PetPolicy.peek(many).more == 11 - PetPolicy.maxPeeked)
    }

    @Test func pipsOnlyWithSeveralSessions() {
        let one = [titled("a", waiting), titled("i", .idle)]
        #expect(!PetPolicy.isMulti(one))
        #expect(PetPolicy.pips(one).shown.isEmpty)
        let three = [titled("a", waiting), titled("b", working), titled("c", working)]
        #expect(PetPolicy.isMulti(three))
        #expect(PetPolicy.pips(three).shown.map(\.sessionId) == ["a", "b", "c"])
        let many = (0..<8).map { titled("w\($0)", working) }
        #expect(PetPolicy.pips(many).shown.count == PetPolicy.maxListed)
        #expect(PetPolicy.pips(many).more == 3)
    }

    @Test func listIsGroupedByUrgencyInAStableOrder() {
        let s = [titled("z", working), titled("b", .done(summary: nil)), titled("a", waiting)]
        #expect(PetPolicy.listed(s).shown.map(\.sessionId) == ["a", "b", "z"])
    }
}

@Suite struct PetReactionGateTests {
    private let t = Date(timeIntervalSince1970: 1_000)

    private func allow(_ gate: inout PetReactionGate, _ r: PetReaction, at date: Date) -> Bool {
        gate.allow(r, at: date)
    }

    @Test func burstsOfTheSameReactionPlayOnce() {
        var gate = PetReactionGate()
        #expect(allow(&gate, .cheer, at: t))
        #expect(!allow(&gate, .cheer, at: t.addingTimeInterval(1)))
        #expect(!allow(&gate, .cheer, at: t.addingTimeInterval(3.9)))
        #expect(allow(&gate, .cheer, at: t.addingTimeInterval(4.1)))
    }

    @Test func somethingMoreUrgentStillGetsThrough() {
        var gate = PetReactionGate()
        #expect(allow(&gate, .cheer, at: t))
        #expect(allow(&gate, .wave, at: t.addingTimeInterval(1)))
        #expect(!allow(&gate, .shake, at: t.addingTimeInterval(2)))
    }

    @Test func theQuietWindowCountsFromTheLastReactionPlayed() {
        var gate = PetReactionGate()
        #expect(allow(&gate, .cheer, at: t))
        #expect(!allow(&gate, .cheer, at: t.addingTimeInterval(3)))
        // Dropped reactions don't extend the window.
        #expect(allow(&gate, .cheer, at: t.addingTimeInterval(4.5)))
    }
}
