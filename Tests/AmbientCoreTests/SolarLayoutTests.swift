import Foundation
import Testing
@testable import AmbientCore

/// A 1512 × 982 MacBook display with a 200 pt notch and the island's menu open (440 × 330).
let macBook = NotchGeometry(screen: Vec2(1512, 982), notchCenterX: 756, notchBottom: 32, notchWidth: 200, menu: Vec2(440, 330))

@Suite struct SolarLayoutTests {
    @Test func oneRowUpToFourThenTwoCentredRows() {
        for n in 1...4 {
            let slots = SolarLayout.rowSlots(count: n)
            #expect(slots.count == n)
            #expect(Set(slots.map(\.y)) == [0.46])
            #expect(abs(slots.map(\.x).reduce(0, +) / Double(n) - 0.5) < 1e-9)
        }
        for n in 5...10 {
            let slots = SolarLayout.rowSlots(count: n)
            #expect(slots.count == n)
            #expect(Set(slots.map(\.y)) == [0.40, 0.60])
            #expect(slots.allSatisfy { $0.x >= 0.09 && $0.x <= 0.91 })
            for row in [0.40, 0.60] {
                let xs = slots.filter { $0.y == row }.map(\.x)
                #expect(abs(xs.reduce(0, +) / Double(xs.count) - 0.5) < 1e-9)
            }
        }
        #expect(SolarLayout.rowSlots(count: 0).isEmpty)
    }

    @Test func theSixMostUrgentOrbitInnermostFirst() {
        let urgencies = [2, 2, 0, 3, 1, 2, 2, 0, 3, 4]
        let agents = urgencies.enumerated().map { NotchAgent(id: "a\($0.offset)", home: .zero, urgency: $0.element) }
        #expect(SolarLayout.orbiters(agents) == ["a2", "a7", "a4", "a0", "a1", "a5"])
        #expect(SolarLayout.orbiters(Array(agents.prefix(3))) == ["a2", "a0", "a1"])
    }

    @Test func orbitsAreEllipsesWithTheFarPointAtTheBottom() {
        let a = 0.5, e = SolarLayout.eccentricity
        #expect(abs(SolarLayout.radius(a: a, theta: .pi / 2) - a * (1 + e)) < 1e-12)
        #expect(abs(SolarLayout.radius(a: a, theta: -.pi / 2) - a * (1 - e)) < 1e-12)
        #expect(SolarLayout.point(a: a, theta: .pi / 2, geometry: macBook).y > macBook.notchBottom)
        #expect(SolarLayout.point(a: a, theta: -.pi / 2, geometry: macBook).y < macBook.notchBottom)
    }

    @Test func periodsFollowKeplersThirdLaw() {
        func period(_ a: Double) -> Double {
            var theta = 0.0, t = 0.0
            let h = 1e-3
            while theta < 2 * .pi { theta += SolarLayout.angularSpeed(a: a, theta: theta) * h; t += h }
            return t
        }
        let ratio = period(0.42) / period(0.72)
        #expect(abs(ratio / pow(0.42 / 0.72, 1.5) - 1) < 0.02)
    }

    @Test func innerOrbitClearsTheMenuAndOuterFitsTheScreen() {
        let orbits = SolarLayout.orbits(count: 6, geometry: macBook)
        #expect(orbits.count == 6)
        #expect(orbits == orbits.sorted())
        let s = SolarLayout.scale(screen: macBook.screen), e = SolarLayout.eccentricity
        #expect(macBook.notchBottom + orbits[0] * (1 + e) * s * SolarLayout.tilt >= macBook.menu.y + 30 - 1e-9)
        #expect(orbits.last! * (1 - e * e).squareRoot() * s <= macBook.screen.x * 0.49 + 1e-6)
        #expect(SolarLayout.orbits(count: 0, geometry: macBook).isEmpty)
        #expect(SolarLayout.orbits(count: 1, geometry: macBook).count == 1)
    }

    @Test func urgencyFollowsMood() {
        #expect([Mood.waiting, .error, .working, .done, .idle].map(NotchAgent.urgency(of:)) == [0, 1, 2, 3, 4])
    }
}
