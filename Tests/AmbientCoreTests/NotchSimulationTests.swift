import Foundation
import Testing
@testable import AmbientCore

/// Three agents where Sky puts them on the MacBook display.
private let trio = [
    NotchAgent(id: "claude", home: Vec2(922, 412), urgency: 0),
    NotchAgent(id: "codex", home: Vec2(544, 472), urgency: 2),
    NotchAgent(id: "gemini", home: Vec2(1346, 471), urgency: 3),
]

private func run(_ sim: inout NotchSimulation, seconds: Double, fps: Double = 60, each: (NotchSimulation) -> Void = { _ in }) {
    for _ in 0..<Int((seconds * fps).rounded()) {
        sim.step(1 / fps)
        each(sim)
    }
}

@Suite struct BlackHoleTests {
    @Test func agentsOrbitTheHoleWithoutBeingSwallowed() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 60, seed: 3)
        sim.setOpen(true)
        var closest = Double.infinity
        var swept = [String: Double](), lastAngle = [String: Double]()
        run(&sim, seconds: 20) { s in
            for b in s.agents {
                let d = b.position - macBook.center
                closest = min(closest, d.length)
                let angle = atan2(d.y, d.x)
                if let last = lastAngle[b.id] {
                    var step = angle - last
                    if step > .pi { step -= 2 * .pi }
                    if step < -.pi { step += 2 * .pi }
                    swept[b.id, default: 0] += abs(step)
                }
                lastAngle[b.id] = angle
            }
        }
        #expect(closest >= 1.5 * macBook.radius)
        #expect(sim.agents.allSatisfy { !$0.absorbed })
        #expect(trio.allSatisfy { (swept[$0.id] ?? 0) > .pi }, "every agent goes at least half way round")
    }

    @Test func dustFallsInAndComesBackAfterClosing() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 150, seed: 5)
        sim.setOpen(true)
        run(&sim, seconds: 10)
        let swallowed = sim.bodies.filter { !$0.isAgent && $0.absorbed }.count
        #expect(swallowed > 0)
        sim.setOpen(false)
        run(&sim, seconds: 1)
        #expect(sim.bodies.allSatisfy { !$0.absorbed })
        #expect(sim.bodies.contains { !$0.isAgent && $0.fade < 1 })
    }

    @Test func afterClosingEveryAgentComesHome() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 40, seed: 9)
        sim.setOpen(true)
        run(&sim, seconds: 8)
        #expect(!sim.isSettled)
        sim.setOpen(false)
        run(&sim, seconds: 6)
        for (agent, body) in zip(trio, sim.agents) {
            #expect((body.position - agent.home).length < 2)
            #expect(body.velocity.length < 5)
        }
        #expect(sim.presence == 0)
        #expect(sim.isSettled)
    }

    @Test func theHoleIsBornOncePerOpening() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 0, seed: 1)
        #expect(sim.presence == 0 && sim.isSettled)
        sim.setOpen(true)
        run(&sim, seconds: 0.3)
        #expect(sim.agents.allSatisfy { $0.velocity.length < 1e-9 }, "no gravity during the collapse")
        #expect(sim.birthFlash > 0 && sim.waveRadius != nil)
        run(&sim, seconds: 1)
        #expect(sim.presence > 0.95 && sim.radius > 0.95 * macBook.radius)
        #expect(sim.agents.allSatisfy { $0.velocity.length > 1 })
    }

    @Test func quickReopenIsClean() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 20, seed: 2)
        sim.setOpen(true); run(&sim, seconds: 0.2)
        sim.setOpen(false); run(&sim, seconds: 0.1)
        sim.setOpen(true); run(&sim, seconds: 0.2)
        #expect(sim.presence >= 0)
        run(&sim, seconds: 2)
        #expect(sim.presence > 0.95)
        #expect(sim.agents.allSatisfy { !$0.absorbed })
    }

    @Test func liftFollowsDistanceFromHome() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 0, seed: 4)
        #expect(sim.lift("claude") == 0)
        sim.setOpen(true)
        run(&sim, seconds: 3)
        #expect(sim.lift("claude") > 0.9)
        #expect(sim.lift("nobody") == 0)
    }
}

@Suite struct SolarSimulationTests {
    /// Eight sessions (the most a scene shows): two need you, one failed, four working, one done.
    private let eight: [NotchAgent] = {
        let urgencies = [2, 2, 0, 3, 1, 2, 2, 0]
        let slots = SolarLayout.rowSlots(count: urgencies.count)
        return urgencies.enumerated().map { i, u in
            NotchAgent(id: "p\(i)", home: Vec2(slots[i].x * macBook.screen.x, slots[i].y * macBook.screen.y), urgency: u)
        }
    }()

    @Test func sixOrbitAndTheRestFallIntoTheSun() {
        var sim = NotchSimulation(mode: .solar, geometry: macBook, agents: eight, dust: 60, seed: 3)
        #expect(sim.agents.filter { $0.orbit != nil }.map(\.id) == ["p0", "p1", "p2", "p4", "p5", "p7"])
        sim.setOpen(true)
        run(&sim, seconds: 3)
        #expect(sim.agents.filter(\.absorbed).map(\.id).sorted() == ["p3", "p6"])
        let orbiting = sim.agents.filter { $0.orbit != nil }
        #expect(orbiting.allSatisfy { !$0.absorbed && $0.velocity.length > 1 })
        // The most urgent get the innermost orbits.
        let orbitOf = Dictionary(uniqueKeysWithValues: orbiting.map { ($0.id, $0.orbit!) })
        #expect(orbitOf["p2"]! < orbitOf["p4"]! && orbitOf["p4"]! < orbitOf["p0"]!)
    }

    @Test func planetsJoinTheirOrbitNearestTheirSlot() {
        var sim = NotchSimulation(mode: .solar, geometry: macBook, agents: eight, dust: 0, seed: 3)
        sim.setOpen(true)
        run(&sim, seconds: 0.3)
        let s = SolarLayout.scale(screen: macBook.screen)
        for body in sim.agents where body.orbit != nil {
            let d = body.home - macBook.center
            let expected = atan2(d.y / (s * SolarLayout.tilt), d.x / s)
            #expect(abs(body.theta - expected) < 0.05)
        }
    }

    @Test func afterClosingEveryPlanetReturnsToItsSlot() {
        var sim = NotchSimulation(mode: .solar, geometry: macBook, agents: eight, dust: 60, seed: 3)
        sim.setOpen(true)
        run(&sim, seconds: 6)
        sim.setOpen(false)
        run(&sim, seconds: 4)
        for (agent, body) in zip(eight, sim.agents) {
            #expect(!body.absorbed)
            #expect((body.position - agent.home).length < 2)
        }
        #expect(sim.isSettled)
        #expect(sim.lift("p0") == 0)
    }

    @Test func agentsCanChangeWhileOpen() {
        var sim = NotchSimulation(mode: .solar, geometry: macBook, agents: eight, dust: 20, seed: 3)
        sim.setOpen(true)
        run(&sim, seconds: 2)
        var changed = Array(eight.dropFirst(2))
        changed.append(NotchAgent(id: "new", home: Vec2(700, 600), urgency: 0))
        sim.setAgents(changed)
        #expect(sim.agents.map(\.id) == changed.map(\.id))
        #expect(sim.agents.first { $0.id == "new" }?.position == Vec2(700, 600))
        #expect(sim.agents.filter { $0.orbit != nil }.count == 6)
        run(&sim, seconds: 2)
        sim.setOpen(false)
        run(&sim, seconds: 4)
        #expect(sim.isSettled)
    }
}

@Suite struct NotchSimulationTests {
    @Test func theSameTimeGivesTheSameResultAtAnyFrameRate() {
        var slow = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 30, seed: 8)
        var fast = slow
        slow.setOpen(true); fast.setOpen(true)
        run(&slow, seconds: 3, fps: 12)
        run(&fast, seconds: 3, fps: 60)
        #expect(abs(slow.time - fast.time) <= NotchSimulation.stepSize + 1e-9)
        for (a, b) in zip(slow.agents, fast.agents) { #expect((a.position - b.position).length < 5) }
    }

    @Test func theSameSeedAndStepsGiveTheSameFrames() {
        var a = NotchSimulation(mode: .solar, geometry: macBook, agents: trio, dust: 40, seed: 11)
        var b = NotchSimulation(mode: .solar, geometry: macBook, agents: trio, dust: 40, seed: 11)
        a.setOpen(true); b.setOpen(true)
        run(&a, seconds: 2); run(&b, seconds: 2)
        #expect(a.bodies == b.bodies)
    }

    @Test func reduceMotionKeepsEveryoneHome() {
        for mode in [NotchSimulation.Mode.blackHole, .solar] {
            var sim = NotchSimulation(mode: mode, geometry: macBook, agents: trio, dust: 20, seed: 2, reduceMotion: true)
            sim.setOpen(true)
            run(&sim, seconds: 4)
            #expect(sim.presence > 0.95)
            #expect(sim.agents.allSatisfy { $0.position == $0.home && !$0.absorbed })
            sim.setOpen(false)
            run(&sim, seconds: 3)
            #expect(sim.isSettled)
        }
    }

    @Test func aFrameStepIsCappedAtAQuarterSecond() {
        var sim = NotchSimulation(mode: .blackHole, geometry: macBook, agents: trio, dust: 0, seed: 1)
        sim.step(10)
        #expect(sim.time <= 0.25 + 1e-9)
    }
}
