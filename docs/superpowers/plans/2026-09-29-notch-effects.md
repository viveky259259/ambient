# Notch Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the island opens, the living wallpaper plays out real physics centred on the notch.
- **Sky, Harbor and Garden:** a black hole that flings agents into Kepler orbits and swallows dust.
- **A new fourth world, Solar System:** planets stand in rows while the island is closed; while it's open, up to six orbit the notch-sun and the rest fall in.

**Architecture:**
- **Physics:** a pure, deterministic simulation in `AmbientCore` (`NotchSimulation`, `SolarLayout`), stepped in fixed 4 ms steps, so frame rate never changes the result.
- **Engine:** in the app, `NotchEffectEngine` owns the simulation for the desk layer on the main display. The scene's life canvas advances it once per frame, and `NotchEffectDrawing` draws it.
- **Island link:** `IslandController` reports when its menu opens.
- **Scene hand-off:**
  - While an effect is engaged, the world fades its own drawing of each lifted agent.
  - The effect draws those agents and their labels instead.
  - Frames run at 60 fps.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI `Canvas` / `TimelineView`, AppKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-29-notch-effects-design.md`. The visual reference is the approved sketches in `.superpowers/brainstorm/31488-1790683372/content/both-kinds-v3.html`.

## Global Constraints

- Branch `feat/living-wallpaper`.
- `AmbientCore` stays Foundation-only in Swift 6 mode; `AmbientApp` builds in Swift 5 mode.
- The physics is tuned on a display 600 pt tall and scaled by `unit = height / 600`:
  - black-hole gravity `5.5e6 · unit³`;
  - solar fall-in gravity `3e7 · unit³`;
  - gravity softening `+400`.
- Fixed physics step: 1/250 s. A frame's time step is capped at 0.25 s.
- Black hole:
  - Collapse: gravity switches on 0.35 s after opening; the hole grows with ease-out-back over 0.18–0.88 s and evaporates over 0.45 s.
  - Agents: closest pass `max(1.9 · R, 0.42 · r)`.
  - Dust: closest pass `r · (0.05 … 0.55)`.
  - Birth wave: speed `1.1 · H` per second, lasting 1.6 s, with an outward kick of `2600 · unit`.
  - Near the disk: drag of 1.8 within `3R`.
  - Swallowing: dust inside `0.98 R`; it comes back 0.8 s after close and fades in at 0.5 per second.
  - Return home: spring 3, damping 3.
- Solar:
  - Orbits: e = 0.45, tilt 0.72, GM 0.045 in plane units.
  - Scale: `min(1.1 H, 0.49 W / (0.72 · √(1 − e²)))`.
  - Orbit sizes: semi-major axes from 0.42 (or larger to clear the menu) to 0.72.
  - Who orbits: at most 6 agents.
  - Moving bodies: spring 7, critically damped.
  - Swallowing: agents inside `14 · unit`.
  - The sun lights over 0.8 s and dims over 1 s.
- Urgency order: needs you 0 › failed 1 › working 2 › done 3 › idle 4.
- Row slots:
  - up to 4 planets: one row at y 0.46;
  - 5 or more: two rows at y 0.40 and 0.60;
  - each row centred, with a span of `min(0.8, 0.2 · (n − 1))`.
- Effects run only on the desk layer of the main display, when that display hosts the island. Never on the lock screen.
- New preference: `wallpaperIslandEffect`, default true: "Black hole when the island opens".
- Logger: `com.viveky259259.Ambient` / `wallpaper`.

## Review Focus

1. **Sessions come and go while the island is open.** A new agent appears at home and joins in, and a vanished agent just disappears. Nothing crashes, and no stale label is left behind. Tested by `agentsCanChangeWhileOpen` in Task 2.
2. **The island opens while the wallpaper is covered, then the desktop is uncovered mid-effect.** The simulation resumes from where it was, with at most a 0.25 s step, and no body leaps across the screen. Handled by the `advance(to:)` cap and the per-open `lastDate` reset in Task 4; checked manually in Task 4.
3. **Quick hover in and out, open → close → open within half a second.** Presence never goes negative, the birth happens once per open, and there's no double collapse. Tested by `quickReopenIsClean` in Task 2.
4. **The island's display isn't the main display** (external monitor as main, notch on the built-in display). No effect, and nothing drawn in the wrong place. Handled by the main-screen check in Task 4; checked manually.
5. **Reduce Motion or Low Power Mode is switched on mid-effect.** The effect stops or becomes stationary at once, and agents are at home. Handled by reconfiguration on change in Task 4; tested by `reduceMotionKeepsEveryoneHome` in Task 2.

## File Map

| File | Status | Responsibility |
| --- | --- | --- |
| `Sources/AmbientCore/NotchGeometry.swift` | new | `Vec2`, `NotchGeometry`, `NotchAgent` |
| `Sources/AmbientCore/SolarLayout.swift` | new | Rows, orbiter choice, Kepler ellipse radius, speed and projection |
| `Sources/AmbientCore/NotchSimulation.swift` | new | Both effects' physics |
| `Sources/AmbientCore/ScenePolicy.swift` | modify | `SceneKind.solar` |
| `Sources/AmbientCore/SceneState.swift` | modify | Solar System shows up to 10 sessions |
| `Tests/AmbientCoreTests/SolarLayoutTests.swift` | new | |
| `Tests/AmbientCoreTests/NotchSimulationTests.swift` | new | |
| `Tests/AmbientCoreTests/DayLightTests.swift` | modify | Daily rotation over four worlds |
| `Sources/AmbientApp/Wallpaper/SceneRenderer.swift` | modify | `spot(for:in:)`, `labelsBelow`, `SceneMotion.lifted`, registry |
| `Sources/AmbientApp/Wallpaper/SkyScene.swift`, `HarborScene.swift`, `GardenScene.swift` | modify | Fade lifted inhabitants |
| `Sources/AmbientApp/Wallpaper/SolarScene.swift` | new | The fourth world, and the planet globe shared with the effect |
| `Sources/AmbientApp/Wallpaper/NotchEffect.swift` | new | `NotchEffectEngine` |
| `Sources/AmbientApp/Wallpaper/NotchEffectDrawing.swift` | new | Black hole and solar drawing, and labels for moving agents |
| `Sources/AmbientApp/Wallpaper/SceneView.swift` | modify | Engaged mode: 60 fps, advance, effect drawing, labels handed to the effect |
| `Sources/AmbientApp/Wallpaper/SceneFeed.swift` | modify | `effect` engine on the feed; `SceneHost` passes it on the main desk window |
| `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift` | modify | Configure the engine; island changes |
| `Sources/AmbientApp/Island/IslandController.swift` | modify | `onMenuChange` |
| `Sources/AmbientApp/AppDelegate.swift` | modify | Wire the island to the wallpaper |
| `Sources/AmbientApp/Preferences.swift` | modify | `wallpaperIslandEffect` |
| `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift` | modify | Toggle |
| `README.md`, `CHANGELOG.md` | modify | Docs |

---

### Task 1: Geometry, solar layout, and the fourth world

**Files:**
- Create: `Sources/AmbientCore/NotchGeometry.swift`
- Create: `Sources/AmbientCore/SolarLayout.swift`
- Create: `Tests/AmbientCoreTests/SolarLayoutTests.swift`
- Modify: `Sources/AmbientCore/ScenePolicy.swift`
- Modify: `Tests/AmbientCoreTests/DayLightTests.swift`
- Modify: `Sources/AmbientCore/SceneState.swift`, `Tests/AmbientCoreTests/SceneStateTests.swift`

**Interfaces:**
- Produces:
  - `struct Vec2 { x, y; + − ×; length; zero }`
  - `struct NotchGeometry { screen: Vec2; notchCenterX, notchBottom, notchWidth: Double; menu: Vec2; center; radius; unit }`
  - `struct NotchAgent { id, home: Vec2, urgency: Int; static urgency(of: Mood) }`
  - `enum SolarLayout`:
    - constants `maxOrbiting`, `eccentricity`, `tilt`, `gm`
    - `rowSlots(count:) -> [Vec2]` (fractions of the screen)
    - `orbiters(_:) -> [String]`
    - `radius(a:theta:)`, `angularSpeed(a:theta:)`
    - `scale(screen:)`
    - `orbits(count:geometry:) -> [Double]`
    - `point(a:theta:geometry:) -> Vec2`
  - `SceneKind.solar` (display name "Solar System")
  - `SceneState.maxInhabitants(for:)` (10 for Solar System, 8 elsewhere)

- [ ] **Step 1: Write the failing tests**

Create `Tests/AmbientCoreTests/SolarLayoutTests.swift`:

```swift
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
```

In `Tests/AmbientCoreTests/DayLightTests.swift`, replace the test `dailyChangesAtMidnightAndCyclesThroughAll` with:

```swift
    @Test func dailyChangesAtMidnightAndCyclesThroughAll() {
        let today = ScenePolicy.kind(for: .daily, on: at(0, 1), calendar: utc)
        #expect(ScenePolicy.kind(for: .daily, on: at(23, 59), calendar: utc) == today)
        let days = (0..<SceneKind.allCases.count).map {
            ScenePolicy.kind(for: .daily, on: at(0, 1).addingTimeInterval(Double($0) * 86_400), calendar: utc)
        }
        #expect(Set(days) == Set(SceneKind.allCases))
        #expect(SceneKind.allCases.contains(.solar))
    }
```

In `Tests/AmbientCoreTests/SceneStateTests.swift`, add inside `SceneStateTests`:

```swift
    @Test func theSolarSystemHoldsTenPlanets() {
        let sessions = (0..<12).map { session("p\($0)", .thinking, lastEvent: TimeInterval(-$0)) }
        let solar = SceneState.make(sessions: sessions, day: DayLog(now: evening, calendar: utc), now: evening,
                                    kind: .solar, surface: .desk, calendar: utc, locale: gb)
        #expect(solar.inhabitants.count == 10)
        #expect(solar.overflow == 2)
        #expect(Set(solar.inhabitants.map(\.slot)).count == 10)
        #expect(make(sessions).inhabitants.count == SceneState.maxInhabitants)
        #expect(SceneState.maxInhabitants(for: .solar) == 10)
        #expect(SceneState.maxInhabitants(for: .garden) == SceneState.maxInhabitants)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "SolarLayoutTests|ScenePolicyTests|SceneStateTests"`
Expected: build failure, `cannot find 'NotchGeometry' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/AmbientCore/NotchGeometry.swift`:

```swift
import Foundation

/// A point or vector in screen points, origin at the top-left.
public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public var length: Double { (x * x + y * y).squareRoot() }
}

/// Where the island is, on the display the wallpaper draws on, in that display's points (origin top-left).
public struct NotchGeometry: Equatable, Sendable {
    /// Width and height of the display.
    public var screen: Vec2
    public var notchCenterX: Double
    /// The notch's bottom edge: the hole's or sun's diameter lies along it.
    public var notchBottom: Double
    public var notchWidth: Double
    /// The island's menu when open (width, height), hanging from the top centre. It's drawn in front.
    public var menu: Vec2

    public init(screen: Vec2, notchCenterX: Double, notchBottom: Double, notchWidth: Double, menu: Vec2) {
        self.screen = screen
        self.notchCenterX = notchCenterX
        self.notchBottom = notchBottom
        self.notchWidth = notchWidth
        self.menu = menu
    }

    public var center: Vec2 { Vec2(notchCenterX, notchBottom) }
    /// The hole's or sun's full radius: half the notch.
    public var radius: Double { notchWidth / 2 }
    /// 1 on a display 600 points tall; the physics is tuned there and scaled.
    public var unit: Double { screen.y / 600 }
}

/// An agent session taking part in a notch effect.
public struct NotchAgent: Equatable, Sendable {
    public let id: String
    /// Where it rests: its spot in the world.
    public var home: Vec2
    /// Lower is more urgent.
    public var urgency: Int

    public init(id: String, home: Vec2, urgency: Int) {
        self.id = id
        self.home = home
        self.urgency = urgency
    }

    /// Needs you › failed › working › done › idle.
    public static func urgency(of mood: Mood) -> Int {
        switch mood {
        case .waiting: 0
        case .error: 1
        case .working: 2
        case .done: 3
        case .idle: 4
        }
    }
}
```

Create `Sources/AmbientCore/SolarLayout.swift`:

```swift
import Foundation

/// The Solar System world's geometry: planets in rows while the island is closed, and Kepler ellipses around the
/// notch-sun while it's open. Orbits lie on a tilted plane; the sun is at a focus and each far point is at the bottom,
/// so planets drift slowly across the lower screen and race round behind the sun.
public enum SolarLayout {
    public static let maxOrbiting = 6
    public static let eccentricity = 0.45
    /// Vertical squash of the orbital plane.
    public static let tilt = 0.72
    /// Gravity in plane units: angular speed is √(gm · a(1 − e²)) / r².
    public static let gm = 0.045

    /// Where `count` planets stand while the island is closed, as fractions of the screen: one row up to four,
    /// two centred rows beyond.
    public static func rowSlots(count: Int) -> [Vec2] {
        guard count > 0 else { return [] }
        let rows = count > 4 ? 2 : 1
        let perRow = (count + rows - 1) / rows
        return (0..<count).map { i in
            let row = i / perRow, column = i % perRow
            let inRow = row == rows - 1 ? count - perRow * (rows - 1) : perRow
            let span = min(0.8, 0.2 * Double(inRow - 1))
            let x = inRow == 1 ? 0.5 : (1 - span) / 2 + span * Double(column) / Double(inRow - 1)
            let y = rows == 1 ? 0.46 : (row == 0 ? 0.40 : 0.60)
            return Vec2(x, y)
        }
    }

    /// The agents that orbit: the most urgent six (ties keep their order), innermost orbit first.
    public static func orbiters(_ agents: [NotchAgent]) -> [String] {
        agents.enumerated()
            .sorted { $0.element.urgency != $1.element.urgency ? $0.element.urgency < $1.element.urgency : $0.offset < $1.offset }
            .prefix(maxOrbiting)
            .map(\.element.id)
    }

    /// Distance from the sun, in plane units, of an orbit with semi-major axis `a` at angle `theta`
    /// (screen-style angles: π/2 points down, where the far point is).
    public static func radius(a: Double, theta: Double) -> Double {
        let e = eccentricity
        return a * (1 - e * e) / (1 - e * sin(theta))
    }

    /// Kepler's second law: fast near the sun, slow far out.
    public static func angularSpeed(a: Double, theta: Double) -> Double {
        let e = eccentricity, r = radius(a: a, theta: theta)
        return (gm * a * (1 - e * e)).squareRoot() / (r * r)
    }

    /// Points per plane unit: the widest orbit (a = 0.72) fits the screen's width.
    public static func scale(screen: Vec2) -> Double {
        min(screen.y * 1.1, screen.x * 0.49 / (0.72 * (1 - eccentricity * eccentricity).squareRoot()))
    }

    /// Semi-major axes for `count` orbiters, innermost first. The innermost far point clears the island's menu.
    public static func orbits(count: Int, geometry: NotchGeometry) -> [Double] {
        guard count > 0 else { return [] }
        let s = scale(screen: geometry.screen)
        let clear = (geometry.menu.y + 30 - geometry.notchBottom) / ((1 + eccentricity) * s * tilt)
        let inner = max(0.42, clear), outer = max(0.72, inner + 0.12)
        guard count > 1 else { return [inner] }
        return (0..<count).map { inner + (outer - inner) * Double($0) / Double(count - 1) }
    }

    /// Where on screen a planet on orbit `a` at angle `theta` is.
    public static func point(a: Double, theta: Double, geometry: NotchGeometry) -> Vec2 {
        let s = scale(screen: geometry.screen), r = radius(a: a, theta: theta)
        return geometry.center + Vec2(cos(theta) * r * s, sin(theta) * r * s * tilt)
    }
}
```

In `Sources/AmbientCore/ScenePolicy.swift`:
- change `case sky, harbor, garden` to `case sky, harbor, garden, solar`;
- add `case .solar: "Solar System"` to `displayName`.

In `Sources/AmbientCore/SceneState.swift`, below `public static let maxInhabitants = 8`, add:

```swift
    /// How many sessions a world shows. Planets in two rows leave room for ten.
    public static func maxInhabitants(for kind: SceneKind) -> Int { kind == .solar ? 10 : maxInhabitants }
```

and in `make`, change `let shown = Array(ordered.prefix(maxInhabitants))` to
`let shown = Array(ordered.prefix(maxInhabitants(for: kind)))`. Change the `overflow` doc comment to
"Sessions beyond what the world shows."

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter "SolarLayoutTests|ScenePolicyTests|SceneStateTests" && swift build`
Expected: all three suites pass. `swift build` fails only because the app's `switch kind` in `SceneRenderers.renderer(for:)` isn't exhaustive. Task 3 adds the case. To keep the build green now, add `case .solar: SkyScene()` there, and Task 3 replaces it.

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/NotchGeometry.swift Sources/AmbientCore/SolarLayout.swift Sources/AmbientCore/ScenePolicy.swift Tests/AmbientCoreTests/SolarLayoutTests.swift Tests/AmbientCoreTests/DayLightTests.swift Sources/AmbientCore/SceneState.swift Tests/AmbientCoreTests/SceneStateTests.swift Sources/AmbientApp/Wallpaper/SceneRenderer.swift
git commit -m "feat(core): notch geometry, solar layout, and the Solar System world"
```

---

### Task 2: The simulation (`NotchSimulation`)

**Files:**
- Create: `Sources/AmbientCore/NotchSimulation.swift`
- Create: `Tests/AmbientCoreTests/NotchSimulationTests.swift`

**Interfaces:**
- Consumes: `Vec2`, `NotchGeometry`, `NotchAgent`, `SolarLayout` (Task 1).
- Produces:
  - `struct NotchSimulation`:
    - `enum Mode { blackHole, solar }`
    - `struct Body { id, isAgent, brightness, position, velocity, home, absorbed, fade, orbit: Double?, theta }`
    - `init(mode:geometry:agents:dust:seed:reduceMotion:)`
    - `setAgents(_:)`, `setOpen(_:)`, `step(_ dt:)`
    - `bodies`, `agents`, `isOpen`, `time`, `sinceOpen`, `sinceClose`, `presence`, `radius`, `waveRadius`, `birthFlash`, `evaporation`, `dustAlpha`, `isSettled`
    - `lift(_ id:) -> Double`
    - `static let stepSize`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AmbientCoreTests/NotchSimulationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "BlackHoleTests|SolarSimulationTests|NotchSimulationTests"`
Expected: build failure, `cannot find 'NotchSimulation' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/AmbientCore/NotchSimulation.swift`:

```swift
import Foundation

/// The physics that plays out on the wallpaper when the island opens, in screen points. Two effects share it.
/// - Black hole: the notch collapses; agents are flung into Kepler orbits and dust falls in. On close, gravity
///   switches off and everything drifts home.
/// - Solar: the notch is the sun; the six most urgent agents orbit it on eccentric ellipses and the rest fall in.
///   On close, every planet returns to its slot in the rows.
///
/// Stepped in fixed 1/250 s steps whatever the frame rate, and deterministic for a seed.
public struct NotchSimulation: Sendable {
    public enum Mode: Equatable, Sendable {
        case blackHole, solar
    }

    public struct Body: Equatable, Sendable {
        public let id: String
        public let isAgent: Bool
        /// 0…1, so dust shines at different strengths.
        public let brightness: Double
        public fileprivate(set) var position: Vec2
        public fileprivate(set) var velocity: Vec2
        public fileprivate(set) var home: Vec2
        public fileprivate(set) var absorbed = false
        /// 0…1: dust fading back in after it was swallowed.
        public fileprivate(set) var fade = 1.0
        /// Solar: the orbit's semi-major axis (plane units) for the agents that orbit, and for the asteroid belt.
        public fileprivate(set) var orbit: Double?
        public fileprivate(set) var theta = 0.0
        fileprivate var spin = 0.0
        fileprivate var entered = false

        fileprivate init(id: String, isAgent: Bool, brightness: Double, home: Vec2) {
            self.id = id
            self.isAgent = isAgent
            self.brightness = brightness
            self.position = home
            self.velocity = .zero
            self.home = home
        }
    }

    public static let stepSize: TimeInterval = 1.0 / 250

    public let mode: Mode
    public let geometry: NotchGeometry
    public let reduceMotion: Bool
    public private(set) var bodies: [Body] = []
    public private(set) var isOpen = false
    public private(set) var time: TimeInterval = 0
    private var openedAt: TimeInterval = -1e9
    private var closedAt: TimeInterval = -1e9
    private var presenceAtClose = 0.0
    private var born = false
    private var pending: TimeInterval = 0
    private var rng: SplitMix

    public init(mode: Mode, geometry: NotchGeometry, agents: [NotchAgent], dust: Int, seed: UInt64 = 7,
                reduceMotion: Bool = false) {
        self.mode = mode
        self.geometry = geometry
        self.reduceMotion = reduceMotion
        rng = SplitMix(seed: seed)
        setAgents(agents)
        switch mode {
        case .blackHole:
            for i in 0..<max(0, dust) {
                let home = Vec2(rng.next() * geometry.screen.x, (0.04 + rng.next() * 0.74) * geometry.screen.y)
                bodies.append(Body(id: "dust-\(i)", isAgent: false, brightness: 0.3 + rng.next() * 0.65, home: home))
            }
        case .solar:
            // The asteroid belt, between the third and fourth orbits of a full system.
            let orbits = SolarLayout.orbits(count: SolarLayout.maxOrbiting, geometry: geometry)
            let lo = orbits[2] + (orbits[3] - orbits[2]) * 0.3, hi = orbits[2] + (orbits[3] - orbits[2]) * 0.7
            for i in 0..<max(0, dust) {
                let a = lo + (hi - lo) * rng.next(), theta = rng.next() * 2 * .pi
                var belt = Body(id: "belt-\(i)", isAgent: false, brightness: 0.25 + rng.next() * 0.5,
                                home: SolarLayout.point(a: a, theta: theta, geometry: geometry))
                belt.orbit = a
                belt.theta = theta
                bodies.append(belt)
            }
        }
    }

    public var agents: [Body] { bodies.filter(\.isAgent) }

    /// Adds, removes and re-homes agents; the ones already there keep their motion. Solar re-picks its six.
    public mutating func setAgents(_ agents: [NotchAgent]) {
        let existing = Dictionary(bodies.filter(\.isAgent).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var agentBodies: [Body] = []
        for agent in agents where seen.insert(agent.id).inserted {
            var body = existing[agent.id] ?? Body(id: agent.id, isAgent: true, brightness: 1, home: agent.home)
            body.home = agent.home
            agentBodies.append(body)
        }
        if mode == .solar {
            let chosen = SolarLayout.orbiters(agents)
            let orbits = SolarLayout.orbits(count: chosen.count, geometry: geometry)
            for i in agentBodies.indices {
                agentBodies[i].orbit = chosen.firstIndex(of: agentBodies[i].id).map { orbits[$0] }
            }
        }
        bodies = agentBodies + bodies.filter { !$0.isAgent }
    }

    public mutating func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        if open {
            openedAt = time
        } else {
            presenceAtClose = presence
            closedAt = time
            born = false
        }
        isOpen = open
    }

    /// Advances by `dt` (at most a quarter second) in fixed steps.
    public mutating func step(_ dt: TimeInterval) {
        pending += max(0, min(dt, 0.25))
        while pending >= Self.stepSize {
            pending -= Self.stepSize
            integrate(Self.stepSize)
        }
    }

    // MARK: - What to draw

    public var sinceOpen: TimeInterval { time - openedAt }
    public var sinceClose: TimeInterval { time - closedAt }

    /// 0…1: how present the hole or the sun is.
    public var presence: Double {
        switch mode {
        case .blackHole:
            if isOpen { return Self.easeOutBack(clamp((sinceOpen - 0.18) / 0.7)) }
            return max(0, 1 - sinceClose / 0.45) * presenceAtClose
        case .solar:
            if isOpen { return clamp(sinceOpen / 0.8) }
            return max(0, 1 - sinceClose / 1.0) * presenceAtClose
        }
    }

    /// The hole's or the sun's radius now.
    public var radius: Double {
        let p = presence
        guard p > 0 else { return 0 }
        return mode == .blackHole ? geometry.radius * p : geometry.radius * (0.6 + 0.4 * p)
    }

    /// The gravitational wave from the hole's birth, while it runs.
    public var waveRadius: Double? {
        guard mode == .blackHole, isOpen, sinceOpen < 1.6 else { return nil }
        return sinceOpen * geometry.screen.y * 1.1
    }

    /// 0…1: the flash as the notch collapses.
    public var birthFlash: Double { mode == .blackHole && isOpen && sinceOpen < 0.5 ? 1 - sinceOpen / 0.5 : 0 }

    /// 0…1: the faint flash as the hole evaporates.
    public var evaporation: Double {
        mode == .blackHole && !isOpen && presenceAtClose > 0 && sinceClose < 0.45 ? 1 - sinceClose / 0.45 : 0
    }

    /// How strongly the effect's own dust shows: fully while open, fading over 2.5 s after closing.
    public var dustAlpha: Double { isOpen ? 1 : max(0, 1 - sinceClose / 2.5) }

    /// Closed, the hole or sun gone, and every agent home and still: the scene can stop drawing the effect.
    public var isSettled: Bool {
        guard !isOpen, presence == 0 else { return false }
        if mode == .blackHole, sinceClose < 2.5 { return false }
        return bodies.allSatisfy { body in
            !body.isAgent || (!body.absorbed && (body.position - body.home).length < 2 && body.velocity.length < 5)
        }
    }

    /// 0 (at home, the world draws it) … 1 (the effect draws it). Solar planets are the effect's while it runs.
    public func lift(_ id: String) -> Double {
        guard let body = bodies.first(where: { $0.isAgent && $0.id == id }) else { return 0 }
        switch mode {
        case .solar: return isSettled ? 0 : 1
        case .blackHole: return body.absorbed ? 1 : clamp((body.position - body.home).length / 30)
        }
    }

    // MARK: - Physics

    private var gravity: Double {
        guard mode == .blackHole, isOpen, sinceOpen >= 0.35 else { return 0 }
        return 5.5e6 * pow(geometry.unit, 3)
    }

    private mutating func integrate(_ h: Double) {
        time += h
        guard !reduceMotion else { return }
        switch mode {
        case .blackHole: integrateBlackHole(h)
        case .solar: integrateSolar(h)
        }
    }

    private mutating func integrateBlackHole(_ h: Double) {
        let c = geometry.center, gm = gravity, holeRadius = radius, height = geometry.screen.y
        if gm > 0, !born {
            // The birth: every body gets the sideways speed of a Kepler ellipse released at its far point.
            // Agents' closest pass stays well outside the hole; dust gets random ones, so some falls in.
            born = true
            for i in bodies.indices where !bodies[i].absorbed {
                let d = bodies[i].position - c, r = max(1, d.length)
                let peri = bodies[i].isAgent ? max(geometry.radius * 1.9, r * 0.42) : r * (0.05 + rng.next() * 0.5)
                let speed = (2 * gm * peri / (r * (r + peri))).squareRoot()
                bodies[i].velocity = bodies[i].velocity + Vec2(-d.y / r, d.x / r) * speed
            }
        }
        let wave = waveRadius
        for i in bodies.indices {
            var b = bodies[i]
            if b.absorbed {
                if !isOpen, sinceClose > 0.8 {
                    b.absorbed = false
                    b.position = b.home
                    b.velocity = .zero
                    b.fade = 0
                }
                bodies[i] = b
                continue
            }
            b.fade = min(1, b.fade + h * 0.5)
            let d = c - b.position, r2 = d.x * d.x + d.y * d.y, r = max(1, r2.squareRoot())
            var a = Vec2.zero
            if gm > 0 {
                a = a + d * (gm / (r2 + 400) / r)
                if !b.isAgent {
                    // The disk's friction bleeds off angular momentum close in, so orbits decay into the hole.
                    let near = clamp(1 - r / (holeRadius * 3 + 1))
                    b.velocity = b.velocity * (1 - near * 1.8 * h)
                }
            }
            if !b.isAgent, let wave, abs(r - wave) < height * 0.05 {
                a = a - d * (2600 * geometry.unit * (1 - sinceOpen / 1.6) / r)
            }
            if !isOpen || gm == 0 {
                // Released: a pull home and drag, so bodies coast on their momentum first, then settle.
                a = a + (b.home - b.position) * 3 - b.velocity * 3
            }
            b.velocity = b.velocity + a * h
            let speed = b.velocity.length, cap = height * 3.5
            if speed > cap { b.velocity = b.velocity * (cap / speed) }
            b.position = b.position + b.velocity * h
            if !b.isAgent, holeRadius > 1, (c - b.position).length < holeRadius * 0.98 { b.absorbed = true }
            bodies[i] = b
        }
    }

    private mutating func integrateSolar(_ h: Double) {
        let c = geometry.center, s = SolarLayout.scale(screen: geometry.screen), tilt = SolarLayout.tilt
        let lit = isOpen && presence > 0.2
        let stiffness = 7.0, damping = 2 * stiffness.squareRoot()
        for i in bodies.indices {
            var b = bodies[i]
            defer { bodies[i] = b }
            if !b.isAgent {
                guard let a = b.orbit else { continue }
                b.spin += ((lit ? 1 : 0) - b.spin) * min(1, h * (isOpen ? 1.6 : 0.8))
                b.theta += b.spin * SolarLayout.angularSpeed(a: a, theta: b.theta) * h
                b.position = SolarLayout.point(a: a, theta: b.theta, geometry: geometry)
                continue
            }
            if let a = b.orbit {
                // One of the six: join the orbit nearest where it stands, then ride it; back to its slot on close.
                if b.absorbed {
                    // Swallowed before it became one of the six (sessions changed): it re-emerges from the sun.
                    b.absorbed = false
                    b.position = c + Vec2(0, 4)
                    b.velocity = .zero
                }
                if lit, !b.entered {
                    let d = b.position - c
                    b.theta = atan2(d.y / (s * tilt), d.x / s)
                    b.entered = true
                }
                if !lit { b.entered = false }
                b.spin += ((lit ? 1 : 0) - b.spin) * min(1, h * (isOpen ? 1.2 : 0.8))
                b.theta += b.spin * SolarLayout.angularSpeed(a: a, theta: b.theta) * h
                let target = lit ? SolarLayout.point(a: a, theta: b.theta, geometry: geometry) : b.home
                b.velocity = b.velocity + ((target - b.position) * stiffness - b.velocity * damping) * h
                b.position = b.position + b.velocity * h
            } else if lit {
                // Not one of the six: it falls into the sun, faster as it nears, and is swallowed.
                guard !b.absorbed else { continue }
                let d = c - b.position, r2 = d.x * d.x + d.y * d.y, r = max(1, r2.squareRoot())
                let g = 3e7 * pow(geometry.unit, 3) / (r2 + 400)
                b.velocity = b.velocity + (d * (g / r) - b.velocity * 0.6) * h
                b.position = b.position + b.velocity * h
                if r < 14 * geometry.unit {
                    b.absorbed = true
                    b.position = c
                    b.velocity = .zero
                }
            } else {
                if b.absorbed {
                    b.absorbed = false
                    b.position = c + Vec2(0, 4)
                    b.velocity = .zero
                }
                b.velocity = b.velocity + ((b.home - b.position) * stiffness - b.velocity * damping) * h
                b.position = b.position + b.velocity * h
            }
        }
    }

    private static func easeOutBack(_ x: Double) -> Double { 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2) }
}

private func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }

/// Repeatable randomness (SplitMix64).
private struct SplitMix: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
```

- [ ] **Step 4: Run them to verify they pass, then the whole suite**

Run: `swift test --filter "BlackHoleTests|SolarSimulationTests|NotchSimulationTests" && swift test`
Expected: all pass. If a physics test is out of tolerance, check the constants against Global Constraints before changing any test.

- [ ] **Step 5: Commit**

```bash
git add Sources/AmbientCore/NotchSimulation.swift Tests/AmbientCoreTests/NotchSimulationTests.swift
git commit -m "feat(core): notch simulation for the black hole and the solar system"
```

---

### Task 3: The Solar System world, and worlds that let agents lift off

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/SolarScene.swift`
- Modify: `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`
- Modify: `Sources/AmbientApp/Wallpaper/SkyScene.swift`, `HarborScene.swift`, `GardenScene.swift`
- Modify: `Sources/AmbientApp/Wallpaper/SceneView.swift` (`SceneTextLayer` only)

**Interfaces:**
- Consumes: `SolarLayout.rowSlots` (Task 1), `SceneKind.solar`.
- Produces:
  - `SceneMotion.lifted: [String: Double]`
  - `SceneRenderer.spot(for:in:) -> CGPoint` (default: `spot(slot, surface:)`)
  - `SceneRenderer.labelsBelow: Bool` (default false)
  - `SolarScene` (`planetRadius(_:u:)`, `planet(_:_:at:radius:sunward:day:date:motion:)`)
  - `SceneTextLayer(state:renderer:size:hidesLabels:)`

- [ ] **Step 1: Renderer protocol, lift, and registry**

In `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`:

Add to `SceneMotion`:

```swift
    /// How far each inhabitant has lifted into a notch effect: 0 at home, 1 carried off. The world fades its own
    /// drawing of it by that much, and the effect draws it instead.
    var lifted: [String: Double] = [:]
```

Add to the `SceneRenderer` protocol:

```swift
    /// Where an inhabitant rests, in unit coordinates. Most worlds use its slot; Solar System lays planets out in rows.
    func spot(for inhabitant: SceneInhabitant, in state: SceneState) -> CGPoint
    /// Labels centred under each inhabitant instead of beside it.
    var labelsBelow: Bool { get }
```

Add after the protocol:

```swift
extension SceneRenderer {
    func spot(for inhabitant: SceneInhabitant, in state: SceneState) -> CGPoint { spot(inhabitant.slot, surface: state.surface) }
    var labelsBelow: Bool { false }
}
```

In `SceneRenderers.renderer(for:)`, the switch becomes:

```swift
        switch kind {
        case .sky: SkyScene()
        case .harbor: HarborScene()
        case .garden: GardenScene()
        case .solar: SolarScene()
        }
```

- [ ] **Step 2: The three worlds fade lifted inhabitants**

In `SkyScene.drawLife`, replace

```swift
        for inhabitant in state.inhabitants {
            star(&ctx, inhabitant, at: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, date: date, motion: motion)
        }
```

with

```swift
        for inhabitant in state.inhabitants {
            let lift = motion.lifted[inhabitant.id] ?? 0
            guard lift < 0.99 else { continue }
            var faded = ctx
            faded.opacity = 1 - lift
            star(&faded, inhabitant, at: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, date: date, motion: motion)
        }
```

In `HarborScene.drawLife`, replace

```swift
        for inhabitant in state.inhabitants {
            boat(&ctx, inhabitant, lantern: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, t: t, date: date, motion: motion, hull: hull)
        }
```

with

```swift
        for inhabitant in state.inhabitants {
            let lift = motion.lifted[inhabitant.id] ?? 0
            guard lift < 0.99 else { continue }
            var faded = ctx
            faded.opacity = 1 - lift
            boat(&faded, inhabitant, lantern: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, t: t, date: date, motion: motion, hull: hull)
        }
```

In `GardenScene.drawLife`, replace

```swift
        for inhabitant in state.inhabitants {
            plant(&ctx, inhabitant, head: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                  size: size, u: u, date: date, motion: motion)
        }
```

with

```swift
        for inhabitant in state.inhabitants {
            let lift = motion.lifted[inhabitant.id] ?? 0
            guard lift < 0.99 else { continue }
            var faded = ctx
            faded.opacity = 1 - lift
            plant(&faded, inhabitant, head: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                  size: size, u: u, date: date, motion: motion)
        }
```

- [ ] **Step 3: Create the Solar System world**

Create `Sources/AmbientApp/Wallpaper/SolarScene.swift`:

```swift
import AmbientCore
import SwiftUI

/// Every session is a planet. While the island is closed they stand in rows across the sky, one row up to four and
/// two beyond. When it opens, the notch becomes the sun and up to six planets orbit it: that part is drawn by the
/// notch effect, which uses this world's planet.
struct SolarScene: SceneRenderer {
    var labelsBelow: Bool { true }

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let slots = SolarLayout.rowSlots(count: SceneState.maxInhabitants(for: .solar))
        let p = slots[((slot % slots.count) + slots.count) % slots.count]
        return CGPoint(x: p.x, y: p.y)
    }

    /// Planets stand in rows in the order of their spots, so the rows stay centred however many there are.
    func spot(for inhabitant: SceneInhabitant, in state: SceneState) -> CGPoint {
        let ordered = state.inhabitants.sorted { $0.slot < $1.slot }
        let index = ordered.firstIndex { $0.id == inhabitant.id } ?? 0
        let p = SolarLayout.rowSlots(count: ordered.count)[index]
        return CGPoint(x: p.x, y: p.y)
    }

    /// No land or water here: all text sits on sky, dark by day.
    func darkInk(_ region: SceneTextRegion, light: DayLight) -> Bool { light.darkInk }

    private struct Look {
        let top, middle, bottom: RGB
        let starlight: Double
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night: Look(top: RGB(hex: "#03040C"), middle: RGB(hex: "#080C22"), bottom: RGB(hex: "#0D1230"), starlight: 1)
        case .dawn: Look(top: RGB(hex: "#1E2150"), middle: RGB(hex: "#4B3F76"), bottom: RGB(hex: "#C98C86"), starlight: 0.4)
        case .day: Look(top: RGB(hex: "#CFE0F5"), middle: RGB(hex: "#E6EEF9"), bottom: RGB(hex: "#F6F8FC"), starlight: 0)
        case .dusk: Look(top: RGB(hex: "#070A1E"), middle: RGB(hex: "#2A2A5C"), bottom: RGB(hex: "#8C4F6E"), starlight: 0.6)
        }
    }

    func drawScenery(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState) {
        let light = state.light
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }
        ctx.fillVertical(CGRect(origin: .zero, size: size), [(0, mix(\.top)), (0.6, mix(\.middle)), (1, mix(\.bottom))])
        // Stars at night; by day, faint dark dust instead.
        let stars = light.amount { Self.look($0).starlight }, day = light.darkInk
        var rng = SceneRandom(seed: 21)
        for _ in 0..<220 {
            let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
            let radius = CGFloat(0.4 + rng.next() * 1.1) * max(size.height / 1000, 0.6)
            let a = 0.2 + rng.next() * 0.6
            let color = day ? Color(red: 0.16, green: 0.2, blue: 0.31).opacity(a * 0.3) : Color.white.opacity(a * stars)
            ctx.fillCircle(at: p, radius: radius, color: color)
        }
    }

    func drawLife(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let u = size.height / 1000
        for inhabitant in state.inhabitants {
            let lift = motion.lifted[inhabitant.id] ?? 0
            guard lift < 0.99 else { continue }
            var faded = ctx
            faded.opacity = 1 - lift
            Self.planet(&faded, inhabitant, at: scenePoint(spot(for: inhabitant, in: state), in: size),
                        radius: Self.planetRadius(inhabitant, u: u), sunward: nil, day: state.light.darkInk,
                        date: date, motion: motion)
        }
    }

    static func planetRadius(_ inhabitant: SceneInhabitant, u: CGFloat) -> CGFloat {
        CGFloat(6 + 5 * inhabitant.busyness) * u
    }

    /// A planet: a globe in its agent's colour, lit from `sunward` (a unit direction toward the sun) while it shines,
    /// in its mood's glow, with a moon circling while it works.
    static func planet(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at p: CGPoint, radius: CGFloat,
                       sunward: CGPoint?, day: Bool, date: Date, motion: SceneMotion) {
        guard radius > 0.3 else { return }
        let body = Palette.agent(inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)
        ctx.fillGlow(at: p, radius: radius * 6,
                     color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color.opacity(level * (day ? 0.75 : 1)))
        let lightFrom = sunward ?? CGPoint(x: -0.4, y: -0.6)
        let shade = day ? Color(red: 0.23, green: 0.25, blue: 0.3) : Color(red: 0.02, green: 0.02, blue: 0.04)
        let gradient = Gradient(stops: [.init(color: .white, location: 0), .init(color: body, location: 0.35),
                                        .init(color: shade, location: 1)])
        let highlight = CGPoint(x: p.x + lightFrom.x * radius * 0.45, y: p.y + lightFrom.y * radius * 0.45)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .radialGradient(gradient, center: highlight, startRadius: radius * 0.1, endRadius: radius))
        guard inhabitant.mood == .working else { return }
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate * 2.4
        ctx.fillCircle(at: CGPoint(x: p.x + CGFloat(cos(t)) * radius * 2.2, y: p.y + CGFloat(sin(t)) * radius * 0.9),
                       radius: max(1.2, radius * 0.22), color: Color(red: 0.8, green: 0.93, blue: 0.9))
    }
}
```

- [ ] **Step 4: Labels under planets, and labels the effect takes over**

In `Sources/AmbientApp/Wallpaper/SceneView.swift`, in `SceneTextLayer`:

Add the property below `let size: CGSize`:

```swift
    /// While a notch effect runs, it draws the inhabitants' labels at their moving bodies.
    var hidesLabels = false
```

Replace `.overlay {\n                labels` with `.overlay {\n                labels\n                    .opacity(hidesLabels ? 0 : 1)`.

Replace the whole `labels` property and `label(_:flipped:)` function with:

```swift
    private var labels: some View {
        ZStack {
            ForEach(state.inhabitants) { inhabitant in
                let spot = renderer.spot(for: inhabitant, in: state)
                if renderer.labelsBelow {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .overlay(alignment: .top) {
                            label(inhabitant, alignment: .center).fixedSize().padding(.top, 20 * u)
                        }
                        .position(x: spot.x * size.width, y: spot.y * size.height)
                } else {
                    // Near the right edge, the label sits to the left of its inhabitant.
                    let flipped = spot.x > 0.72
                    Color.clear
                        .frame(width: 1, height: 1)
                        .overlay(alignment: flipped ? .trailing : .leading) {
                            label(inhabitant, alignment: flipped ? .trailing : .leading)
                                .fixedSize()
                                .padding(flipped ? .trailing : .leading, 22 * u)
                        }
                        .position(x: spot.x * size.width, y: spot.y * size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func label(_ inhabitant: SceneInhabitant, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2 * u) {
            Text(inhabitant.headline)
                .font(.system(size: 12.5 * u, weight: .semibold))
                .foregroundStyle(inhabitant.mood == .waiting ? waitingInk : ink(.labels))
            Text(inhabitant.place).font(.system(size: 12 * u)).opacity(0.75)
            if let detail = inhabitant.detail {
                Text(detail).font(.system(size: 11 * u, design: .monospaced)).opacity(0.6)
            }
        }
        .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    }
```

- [ ] **Step 5: Build and look at the new world**

Run: `swift build && swift test`
Expected: clean build; all tests pass.

Render Solar System through the offscreen harness in `.superpowers/sdd/2026-09-29-notch-effects/harness`. Copy it from `.superpowers/sdd/2026-09-29-living-wallpaper/harness`, and add `Wallpaper/SolarScene.swift` to `sync.sh`. Render at night and by day, with 3 and 8 sessions. Check:
- one row with 3 sessions, and two centred rows with 8;
- each label centred under its planet;
- dark text by day.

- [ ] **Step 6: Commit**

```bash
git add Sources/AmbientApp/Wallpaper
git commit -m "feat(app): Solar System world; worlds fade agents lifted into a notch effect"
```

---

### Task 4: The effect: engine, drawing, and the island link

**Files:**
- Create: `Sources/AmbientApp/Wallpaper/NotchEffect.swift`
- Create: `Sources/AmbientApp/Wallpaper/NotchEffectDrawing.swift`
- Modify: `Sources/AmbientApp/Wallpaper/SceneView.swift` (the `SceneView` struct)
- Modify: `Sources/AmbientApp/Wallpaper/SceneFeed.swift`
- Modify: `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- Modify: `Sources/AmbientApp/Island/IslandController.swift`
- Modify: `Sources/AmbientApp/AppDelegate.swift`
- Modify: `Sources/AmbientApp/Preferences.swift`
- Modify: `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`

**Interfaces:**
- Consumes: `NotchSimulation`, `NotchGeometry`, `NotchAgent`, `SolarLayout` (Tasks 1–2); `SolarScene.planet/planetRadius`, `SceneMotion.lifted`, `spot(for:in:)`, `SceneTextLayer(hidesLabels:)` (Task 3).
- Produces:
  - `final class NotchEffectEngine: ObservableObject`:
    - `@Published engaged`, `simulation`, `trails`, `lifted`
    - `configure(mode:geometry:agents:reduceMotion:)`, `setOpen(_:)`, `advance(to:)`
  - `enum NotchEffectDrawing { static func draw(_:size:engine:state:date:motion:showsLabels:) }`
  - `SceneView(... effect:engaged:)` and `EffectSceneView(state:effect:animated:reduceMotion:)`
  - `SceneFeed.effect`
  - `IslandController.onMenuChange: ((Bool, CGSize) -> Void)?` (open, the expanded menu's size)
  - `LivingWallpaper.islandChanged(open:menu:)`
  - `Preferences.wallpaperIslandEffect`

- [ ] **Step 1: The engine**

Create `Sources/AmbientApp/Wallpaper/NotchEffect.swift`:

```swift
import AmbientCore
import Combine
import Foundation

/// Runs a notch effect on the desk layer of the display with the island. The scene's life canvas advances it once
/// per frame; `engaged` tells views to run at full frame rate and let the effect draw the agents and their labels.
final class NotchEffectEngine: ObservableObject {
    @Published private(set) var engaged = false
    private(set) var simulation: NotchSimulation?
    /// Recent positions of each agent, for trails.
    private(set) var trails: [String: [CGPoint]] = [:]
    private var lastDate: Date?

    /// Sets the effect up, or tears it down with a nil mode or geometry. Agents keep their motion across updates.
    func configure(mode: NotchSimulation.Mode?, geometry: NotchGeometry?, agents: [NotchAgent], reduceMotion: Bool) {
        guard let mode, let geometry else {
            simulation = nil
            trails = [:]
            if engaged { engaged = false }
            return
        }
        // While the effect runs, a menu that grows or shrinks by a row doesn't restart it.
        if var sim = simulation, sim.mode == mode, sim.reduceMotion == reduceMotion,
           sim.geometry == geometry || (engaged && sim.geometry.screen == geometry.screen) {
            sim.setAgents(agents)
            simulation = sim
        } else {
            let wasOpen = simulation?.isOpen ?? false
            var sim = NotchSimulation(mode: mode, geometry: geometry, agents: agents,
                                      dust: mode == .blackHole ? 180 : 160, reduceMotion: reduceMotion)
            if wasOpen { sim.setOpen(true) }
            simulation = sim
            trails = [:]
            lastDate = nil
        }
    }

    func setOpen(_ open: Bool) {
        guard simulation != nil else { return }
        simulation?.setOpen(open)
        lastDate = nil   // a frame paused while covered picks up without a leap
        if open, !engaged { engaged = true }
    }

    /// Steps the simulation to `date`. Called from the scene's life canvas, once per frame.
    func advance(to date: Date) {
        guard var sim = simulation else { return }
        sim.step(lastDate.map { date.timeIntervalSince($0) } ?? 0)
        lastDate = date
        simulation = sim
        for body in sim.agents {
            var trail = trails[body.id] ?? []
            trail.append(CGPoint(x: body.position.x, y: body.position.y))
            if trail.count > 50 { trail.removeFirst(trail.count - 50) }
            trails[body.id] = trail
        }
        if sim.isSettled, engaged {
            // Publishing from inside a view update isn't allowed: hop to the next turn of the run loop.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.simulation?.isSettled == true, self.engaged else { return }
                self.engaged = false
                self.trails = [:]
            }
        }
    }

    /// How far each agent has lifted into the effect.
    var lifted: [String: Double] {
        guard let sim = simulation else { return [:] }
        return Dictionary(sim.agents.map { ($0.id, sim.lift($0.id)) }, uniquingKeysWith: { first, _ in first })
    }
}
```

- [ ] **Step 2: The drawing**

Create `Sources/AmbientApp/Wallpaper/NotchEffectDrawing.swift`:

```swift
import AmbientCore
import SwiftUI

/// Draws a running notch effect over the scene's life: the black hole with its gravity sheet, dust and orbs, or
/// the sun with its orbits, belt and planets. The island's own menu is drawn by the island, in front of all this.
enum NotchEffectDrawing {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, engine: NotchEffectEngine, state: SceneState,
                     date: Date, motion: SceneMotion, showsLabels: Bool) {
        guard let sim = engine.simulation, sim.geometry.screen.x > 0 else { return }
        // The simulation works in the screen's points; a thumbnail or a scaled window draws it smaller.
        let k = size.width / sim.geometry.screen.x
        var ctx = ctx
        ctx.scaleBy(x: k, y: k)
        let look = Look(day: state.light.darkInk, unit: sim.geometry.unit)
        let inhabitants = Dictionary(state.inhabitants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let t = motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        switch sim.mode {
        case .blackHole:
            blackHole(&ctx, sim, engine: engine, inhabitants: inhabitants, look: look, t: t, date: date, motion: motion,
                      showsLabels: showsLabels)
        case .solar:
            solar(&ctx, sim, engine: engine, inhabitants: inhabitants, look: look, t: t, date: date, motion: motion,
                  showsLabels: showsLabels)
        }
    }

    /// Colours for the time of day: the light look by day, the dark look at dawn, dusk and night.
    struct Look {
        let day: Bool
        let unit: Double
        var grid: Color { day ? Color(red: 0.16, green: 0.24, blue: 0.47) : Color(red: 0.55, green: 0.63, blue: 1) }
        var dust: (Double, Double, Double) { day ? (0.16, 0.2, 0.31) : (1, 1, 1) }
        var ring: Color { day ? Color(red: 0.16, green: 0.24, blue: 0.47) : Color(red: 0.63, green: 0.7, blue: 1) }
        var belt: Color { day ? Color(red: 0.43, green: 0.37, blue: 0.31) : Color(red: 0.82, green: 0.78, blue: 0.75) }
        var ink: Color { day ? Color(white: 0.08) : .white }
        var waiting: Color { day ? Color(red: 0.66, green: 0.38, blue: 0) : Color(red: 0.96, green: 0.73, blue: 0.29) }
        var glow: Double { day ? 0.75 : 1 }
        var u: CGFloat { CGFloat(unit) }
    }

    // MARK: - Black hole

    private static func blackHole(_ ctx: inout GraphicsContext, _ sim: NotchSimulation, engine: NotchEffectEngine,
                                  inhabitants: [String: SceneInhabitant], look: Look, t: Double, date: Date,
                                  motion: SceneMotion, showsLabels: Bool) {
        let c = cg(sim.geometry.center), R = CGFloat(sim.radius), grow = sim.presence, u = look.u
        let screen = CGSize(width: sim.geometry.screen.x, height: sim.geometry.screen.y)

        // The gravity sheet: a grid sinking into a well at the hole, fading with distance, rippling with the
        // birth's wave. Only while the hole is there.
        if R > 0.5 {
            let notchR = CGFloat(sim.geometry.radius), wave = sim.waveRadius.map { CGFloat($0) }
            func warp(_ p: CGPoint) -> (CGPoint, CGFloat) {
                let dx = p.x - c.x, dy = p.y - c.y, r = max(1, hypot(dx, dy))
                var pull = CGFloat(grow) * notchR * 1.35 * notchR / (r + notchR * 0.35)
                pull = min(pull, max(0, r - notchR * 0.55))
                var ripple: CGFloat = 0
                if let wave {
                    let d = r - wave
                    ripple = 9 * u * exp(-(d * d) / (2 * pow(28 * u, 2))) * sin(d / (9 * u)) * CGFloat(1 - sim.sinceOpen / 1.6)
                }
                let k = (r - pull + ripple) / r
                return (CGPoint(x: c.x + dx * k, y: c.y + dy * k), pull / r)
            }
            let step = 34 * u, reach = screen.height * 0.9
            for pass in 0..<2 {
                let lines = Int((pass == 0 ? screen.height : screen.width) / step) + 1
                let samples = Int((pass == 0 ? screen.width : screen.height) / 8)
                for i in 0...lines {
                    var path = Path(), bend: CGFloat = 0
                    for j in 0...samples {
                        let p0 = pass == 0 ? CGPoint(x: CGFloat(j) * 8, y: CGFloat(i) * step)
                                           : CGPoint(x: CGFloat(i) * step, y: CGFloat(j) * 8)
                        let (p, b) = warp(p0)
                        bend = max(bend, b)
                        if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    // Lines far from the hole barely show: the sheet is only felt near the well.
                    let lineDistance = pass == 0 ? CGFloat(i) * step - c.y : abs(CGFloat(i) * step - c.x)
                    let near = min(1, max(0, 1 - lineDistance / reach))
                    let alpha = (0.05 + min(0.22, bend * 0.5)) * near * CGFloat(grow)
                    ctx.stroke(path, with: .color(look.grid.opacity(alpha)), lineWidth: 1)
                }
            }
        }

        // Dust: stretched along its fall by tidal force, reddened near the horizon.
        let (dr, dg, db) = look.dust
        for body in sim.bodies where !body.isAgent && !body.absorbed {
            let p = cg(body.position), dx = p.x - c.x, dy = p.y - c.y, r = max(1, hypot(dx, dy))
            let tidal = R > 1 ? min(14, pow(R * 2.2 / r, 3)) : 0
            let length = min(60, tidal * 2.5 + CGFloat(body.velocity.length) * 0.018)
            let heat = R > 1 ? min(1, max(0, R * 3 / r - 0.8)) : 0
            let color = Color(red: dr + (1 - dr) * heat, green: dg + (0.53 - dg) * heat, blue: db + (0.22 - db) * heat)
                .opacity(body.brightness * body.fade * sim.dustAlpha * (look.day ? 0.6 : 1))
            let size = CGFloat(0.5 + body.brightness) * u
            if length > 1.2 {
                var line = Path()
                line.move(to: CGPoint(x: p.x - dx / r * length / 2, y: p.y - dy / r * length / 2))
                line.addLine(to: CGPoint(x: p.x + dx / r * length / 2, y: p.y + dy / r * length / 2))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: max(0.6, size * (1 - 0.4 * heat)), lineCap: .round))
            } else {
                ctx.fillCircle(at: p, radius: size, color: color)
            }
        }

        // Agents, lifted off as light: an orb in the agent's colour with its mood glow, trailing its path.
        for body in sim.agents where !body.absorbed {
            guard let inhabitant = inhabitants[body.id] else { continue }
            let lift = sim.lift(body.id)
            guard lift > 0.01 else { continue }
            let p = cg(body.position)
            trail(&ctx, engine.trails[body.id], color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color,
                  width: 2 * u, alpha: 0.55 * lift)
            var orb = ctx
            orb.opacity = lift
            let level = max(0.35, glowLevel(inhabitant, date: date, motion: motion))
            orb.fillGlow(at: p, radius: 60 * u,
                         color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color.opacity(level * look.glow))
            orb.fillCircle(at: p, radius: 5 * u, color: .white)
            orb.fillCircle(at: p, radius: 2.4 * u, color: Palette.agent(inhabitant.agent).color)
            if showsLabels { label(&orb, inhabitant, at: CGPoint(x: p.x + 14 * u, y: p.y), anchor: .leading, look: look) }
        }

        // The hole itself, centred on the notch's bottom edge: only its lower half shows below the notch.
        if R > 0.5 {
            let g = CGFloat(grow), spin = t * 1.4, diskOut = R * 3.4
            // The accretion disk along the notch line, brighter on the side turning toward you.
            for i in 0..<70 {
                let f = CGFloat(i) / 69, x = c.x - diskOut + f * diskOut * 2, rr = abs(x - c.x)
                guard rr >= R * 1.02 else { continue }
                let heat = min(1, max(0, 1 - (rr - R) / (diskOut - R))), doppler: CGFloat = x < c.x ? 1 : 0.55
                let th = R * 0.075 * (0.4 + heat)
                ctx.fill(Path(CGRect(x: x, y: c.y - th, width: diskOut * 2 / 69 + 1, height: th * 2)),
                         with: .color(Color(red: 1, green: (170 + 70 * heat) / 255, blue: (90 + 120 * heat) / 255)
                            .opacity(0.85 * heat * doppler * g)))
            }
            for i in 0..<26 {
                let a = Double(i) / 26 * 2 * .pi + spin * (1.8 - Double(i % 5) * 0.2)
                let rr = R * (1.15 + CGFloat(i % 7) * 0.32)
                let x = c.x + CGFloat(cos(a)) * rr, y = c.y + CGFloat(sin(a)) * rr * 0.06
                if abs(x - c.x) < R * 1.02, y > c.y - 2 { continue }
                ctx.fill(Path(CGRect(x: x - 5 * u, y: y - 0.8 * u, width: 10 * u, height: 1.6 * u)),
                         with: .color(Color(red: 1, green: 0.93, blue: 0.78).opacity(0.55 * g * (cos(a) < 0 ? 1 : 0.5))))
            }
            // The far side of the disk, bent by the hole's gravity into arcs beneath it.
            for j in 0..<3 {
                var arc = Path()
                arc.addArc(center: c, radius: R * (1.12 + CGFloat(j) * 0.08), startAngle: .radians(0.05),
                           endAngle: .radians(.pi - 0.05), clockwise: false)
                ctx.stroke(arc, with: .color(Color(red: 1, green: (200 - 30 * Double(j)) / 255, blue: (140 - 30 * Double(j)) / 255)
                    .opacity((0.7 - 0.2 * Double(j)) * g)), style: StrokeStyle(lineWidth: (3.2 - CGFloat(j)) * u, lineCap: .round))
            }
            // The shadow, and the photon ring on its rim.
            ctx.fill(halfDisk(c, R * 1.06), with: .radialGradient(
                Gradient(stops: [.init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0), location: 0.9),
                                 .init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.95 * g), location: 0.95),
                                 .init(color: Color(red: 1, green: 0.78, blue: 0.55).opacity(0), location: 1)]),
                center: c, startRadius: 0, endRadius: R * 1.06))
            ctx.fill(halfDisk(c, R * 0.97), with: .color(.black))
        }

        // The flash as the notch collapses, the wave's crest, and the faint flash as the hole evaporates.
        if sim.birthFlash > 0 {
            let r = CGFloat(sim.geometry.notchWidth) * 1.1
            ctx.fillGlow(at: c, radius: r, color: Color(red: 1, green: 0.96, blue: 0.9).opacity(0.7 * sim.birthFlash))
        }
        if let wave = sim.waveRadius {
            var crest = Path()
            crest.addArc(center: c, radius: CGFloat(wave), startAngle: .zero, endAngle: .radians(.pi), clockwise: false)
            ctx.stroke(crest, with: .color(look.grid.opacity(0.45 * (1 - sim.sinceOpen / 1.6))), lineWidth: 2.5 * u)
        }
        if sim.evaporation > 0 {
            ctx.fillGlow(at: c, radius: CGFloat(sim.geometry.notchWidth) * 0.8,
                         color: Color(red: 0.82, green: 0.88, blue: 1).opacity(0.6 * sim.evaporation))
        }
    }

    // MARK: - Solar System

    private static func solar(_ ctx: inout GraphicsContext, _ sim: NotchSimulation, engine: NotchEffectEngine,
                              inhabitants: [String: SceneInhabitant], look: Look, t: Double, date: Date,
                              motion: SceneMotion, showsLabels: Bool) {
        let geometry = sim.geometry, c = cg(geometry.center), light = sim.presence, u = look.u
        let s = SolarLayout.scale(screen: geometry.screen), e = SolarLayout.eccentricity, tilt = SolarLayout.tilt
        let screenHeight = CGFloat(geometry.screen.y)

        // Orbit rings: ellipses with the sun at a focus, their centre a·e below it.
        for a in Set(sim.agents.compactMap(\.orbit)).sorted() {
            let rx = CGFloat(a * (1 - e * e).squareRoot() * s), ry = CGFloat(a * s * tilt)
            let cy = c.y + CGFloat(a * e * s * tilt)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: cy - ry, width: rx * 2, height: ry * 2)),
                       with: .color(look.ring.opacity(0.04 + 0.16 * light)), lineWidth: 1)
        }
        // The asteroid belt.
        for body in sim.bodies where !body.isAgent {
            let depth = CGFloat(1 + 0.35 * sin(body.theta))
            ctx.fillCircle(at: cg(body.position), radius: CGFloat(0.5 + body.brightness) * u * depth,
                           color: look.belt.opacity(body.brightness * (0.6 + 0.4 * light) * sim.dustAlpha))
        }

        // The sun: its diameter is the notch line. Corona, slow flares, and the lit disk.
        if light > 0.01 {
            let R = CGFloat(sim.radius), l = light
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 4.2, y: c.y - R * 4.2, width: R * 8.4, height: R * 8.4)),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: Color(red: 1, green: 0.84, blue: 0.55).opacity(0.75 * l), location: 0.19),
                        .init(color: Color(red: 1, green: 0.59, blue: 0.27).opacity(0.25 * l), location: 0.45),
                        .init(color: Color(red: 1, green: 0.47, blue: 0.16).opacity(0), location: 1)]),
                        center: c, startRadius: 0, endRadius: R * 4.2))
            for i in 0..<9 {
                let a = Double(i) / 9 * .pi + sin(t * 0.7 + Double(i)) * 0.15
                let length = R * CGFloat(1.25 + 0.25 * sin(t * 1.3 + Double(i) * 2.1))
                var flare = Path()
                flare.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * R, y: c.y + CGFloat(sin(a)) * R))
                flare.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * length, y: c.y + CGFloat(sin(a)) * length))
                ctx.stroke(flare, with: .color(Color(red: 1, green: 0.75, blue: 0.43).opacity(0.28 * l)),
                           style: StrokeStyle(lineWidth: 3 * u, lineCap: .round))
            }
            ctx.fill(halfDisk(c, R), with: .radialGradient(Gradient(stops: [
                .init(color: Color(red: 1, green: 0.99, blue: 0.92).opacity(l), location: 0),
                .init(color: Color(red: 1, green: 0.82, blue: 0.47).opacity(l), location: 0.7),
                .init(color: Color(red: 1, green: 0.59, blue: 0.24).opacity(l), location: 1)]),
                center: CGPoint(x: c.x, y: c.y - R * 0.2), startRadius: 0, endRadius: R))
        }

        // Planets, far ones first so near ones pass in front.
        let order = sim.agents.filter { !$0.absorbed }.sorted { depth($0) < depth($1) }
        for body in order {
            guard let inhabitant = inhabitants[body.id] else { continue }
            let p = cg(body.position)
            // Falling into the sun, a planet shrinks as it nears it.
            let near = body.orbit != nil ? 1 : min(1, CGFloat((body.position - geometry.center).length) / (screenHeight * 0.3))
            let d = CGFloat(body.orbit != nil ? 1 + (1 + 0.35 * sin(body.theta) - 1) * light : 1) * near
            if body.velocity.length > 8 {
                trail(&ctx, engine.trails[body.id], color: Palette.agent(inhabitant.agent).color, width: 2 * u, alpha: 0.45)
            }
            let toSun = CGPoint(x: c.x - p.x, y: c.y - p.y), length = max(1, hypot(toSun.x, toSun.y))
            let sunward = light > 0.05 ? CGPoint(x: toSun.x / length * CGFloat(light), y: toSun.y / length * CGFloat(light)) : nil
            // The world's own planet size, so nothing jumps when the world takes a planet back.
            let radius = SolarScene.planetRadius(inhabitant, u: screenHeight / 1000) * d
            SolarScene.planet(&ctx, inhabitant, at: p, radius: radius, sunward: sunward, day: look.day, date: date, motion: motion)
            // Labels once a planet is clear of the notch and not shrinking into the sun: centred under it in the rows,
            // beside it in orbit.
            guard showsLabels, p.y > c.y + 8, near > 0.9 else { continue }
            if light < 0.5 || body.orbit == nil {
                label(&ctx, inhabitant, at: CGPoint(x: p.x, y: p.y + radius + 12 * u), anchor: .top, look: look)
            } else {
                label(&ctx, inhabitant, at: CGPoint(x: p.x + radius + 10 * u, y: p.y), anchor: .leading, look: look)
            }
        }
    }

    // MARK: - Pieces

    private static func depth(_ body: NotchSimulation.Body) -> Double { body.orbit != nil ? sin(body.theta) : 2 }

    private static func cg(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }

    /// The lower half of a disk: the half below the notch line.
    private static func halfDisk(_ c: CGPoint, _ r: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: c.x + r, y: c.y))
        path.addArc(center: c, radius: r, startAngle: .zero, endAngle: .radians(.pi), clockwise: false)
        path.closeSubpath()
        return path
    }

    private static func trail(_ ctx: inout GraphicsContext, _ points: [CGPoint]?, color: Color, width: CGFloat, alpha: Double) {
        guard let points, points.count > 2 else { return }
        for i in 1..<points.count {
            let f = Double(i) / Double(points.count)
            var segment = Path()
            segment.move(to: points[i - 1])
            segment.addLine(to: points[i])
            ctx.stroke(segment, with: .color(color.opacity(alpha * f)), lineWidth: width * CGFloat(f))
        }
    }

    /// A moving agent's label: its headline, in the ink for the time of day.
    private static func label(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at point: CGPoint,
                              anchor: UnitPoint, look: Look) {
        let text = Text(inhabitant.headline)
            .font(.system(size: 11.5 * look.u, weight: .semibold))
            .foregroundColor(inhabitant.mood == .waiting ? look.waiting : look.ink)
        ctx.draw(text, at: point, anchor: anchor)
    }
}
```

- [ ] **Step 3: The scene runs the effect while it's engaged**

In `Sources/AmbientApp/Wallpaper/SceneView.swift`, replace the `SceneView` struct (everything above `SceneTextLayer`) with:

```swift
/// A living wallpaper: one world, its inhabitants, and the text set into it.
struct SceneView: View {
    let state: SceneState
    /// False on displays other than the main one, and for thumbnails.
    var showsText = true
    /// False draws one still frame: while covered, in Low Power Mode, for thumbnails and for the lock-screen fallback image.
    var animated = true
    var reduceMotion = false
    /// The notch effect on the island's display, and whether it's running now.
    var effect: NotchEffectEngine?
    var engaged = false

    var body: some View {
        let renderer = SceneRenderers.renderer(for: state.kind)
        let motion = SceneMotion(reduce: reduceMotion, still: !animated)
        let running = animated && engaged && effect != nil
        ZStack {
            // The scenery and the text only change with the state, so they aren't redrawn on every frame.
            Canvas { ctx, size in renderer.drawScenery(&ctx, size: size, state: state) }
            if running, let effect {
                // The effect: every frame advances the physics, then draws the world's life (less what's lifted into
                // the effect) and the effect over it.
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { context in
                    Canvas { ctx, size in
                        effect.advance(to: context.date)
                        var lifted = motion
                        lifted.lifted = effect.lifted
                        renderer.drawLife(&ctx, size: size, state: state, date: context.date, motion: lifted)
                        NotchEffectDrawing.draw(&ctx, size: size, engine: effect, state: state, date: context.date,
                                                motion: lifted, showsLabels: showsText)
                    }
                }
            } else if animated {
                TimelineView(.animation(minimumInterval: Self.frameInterval(state), paused: false)) { context in
                    Canvas { ctx, size in renderer.drawLife(&ctx, size: size, state: state, date: context.date, motion: motion) }
                }
            } else {
                Canvas { ctx, size in renderer.drawLife(&ctx, size: size, state: state, date: state.now, motion: motion) }
            }
            if showsText {
                GeometryReader { geo in
                    SceneTextLayer(state: state, renderer: renderer, size: geo.size, hidesLabels: running)
                }
            }
        }
    }

    /// About 12 frames a second while something moves (enough for a calm wallpaper); one a second when everything rests.
    static func frameInterval(_ state: SceneState) -> Double {
        let moving = state.inhabitants.contains { $0.mood != .idle } || arrivalProgress(of: state.marks, at: Date()) != nil
        return moving ? 1.0 / 12 : 1
    }
}

/// The main desk scene, watching its notch effect so it switches to full frame rate while the effect runs.
struct EffectSceneView: View {
    let state: SceneState
    @ObservedObject var effect: NotchEffectEngine
    var animated = true
    var reduceMotion = false

    var body: some View {
        SceneView(state: state, animated: animated, reduceMotion: reduceMotion, effect: effect, engaged: effect.engaged)
    }
}
```

- [ ] **Step 4: The feed carries the engine to the main desk window**

In `Sources/AmbientApp/Wallpaper/SceneFeed.swift`:

Add to `SceneFeed`, below `@Published var reduceMotion = false`:

```swift
    /// The notch effect, drawn only by the desk scene on the main display.
    let effect = NotchEffectEngine()
```

Replace the body of `SceneHost` with:

```swift
    var body: some View {
        if let state = surface == .desk ? feed.desk : feed.lock {
            let animated = surface == .desk ? feed.deskAnimated : feed.lockAnimated
            if surface == .desk, isMain {
                EffectSceneView(state: state, effect: feed.effect, animated: animated, reduceMotion: feed.reduceMotion)
            } else {
                SceneView(state: isMain ? state : state.scenery(), showsText: isMain, animated: animated,
                          reduceMotion: feed.reduceMotion)
            }
        } else {
            Color.black
        }
    }
```

- [ ] **Step 5: The island says when its menu opens**

In `Sources/AmbientApp/Island/IslandController.swift`:

Add below `private var hoverSuppressed = false`:

```swift
    /// Called when the menu opens or closes, with the open menu's size.
    var onMenuChange: ((Bool, CGSize) -> Void)?
```

In `refresh()`, replace `if next != viewModel.presentation { viewModel.presentation = next }` with:

```swift
        if next != viewModel.presentation {
            let wasOpen = viewModel.presentation == .expanded
            viewModel.presentation = next
            if (next == .expanded) != wasOpen { onMenuChange?(next == .expanded, viewModel.size(for: .expanded)) }
        }
```

- [ ] **Step 6: The setting**

In `Sources/AmbientApp/Preferences.swift`:
- add below `wallpaperCalendar`'s declaration:
  `@Published var wallpaperIslandEffect: Bool { didSet { defaults.set(wallpaperIslandEffect, forKey: "wallpaperIslandEffect") } }`
- add `"wallpaperIslandEffect": true,` to the registered defaults after `"wallpaperCalendar": false,`
- add `wallpaperIslandEffect = defaults.bool(forKey: "wallpaperIslandEffect")` after `wallpaperCalendar = …` in `init`.

In `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, replace

```swift
                SettingsSection(header: "Scene") {
                    ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
                }
```

with

```swift
                SettingsSection(header: "Scene",
                                footer: "When you open the island, the Solar System's sun lights and its planets orbit. The other scenes can form a black hole at the notch.") {
                    ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
                    SettingsDivider()
                    SettingsToggleRow(title: "Black hole when the island opens", isOn: $prefs.wallpaperIslandEffect)
                        .disabled(prefs.sceneChoice == .fixed(.solar))
                }
```

- [ ] **Step 7: The wallpaper drives the engine**

In `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`:

Add below `private var lastSwapMoods: [Mood] = []`:

```swift
    private var islandOpen = false
    /// The island's open menu, so orbits run clear of it. A guess until the island first opens.
    private var menuSize = CGSize(width: 440, height: 330)
```

Add to the `MARK: - What the scene shows` section, after `refresh()`:

```swift
    /// The island opened or closed: the effect starts, or winds down and settles.
    func islandChanged(open: Bool, menu: CGSize) {
        islandOpen = open
        menuSize = menu
        configureEffect()
        feed.effect.setOpen(open)
    }

    /// Sets the notch effect up for the scene now showing: Solar System always lights its sun; the other worlds
    /// form a black hole if the setting is on. None in Low Power Mode, or when the island isn't on the main display.
    private func configureEffect() {
        guard let desk = feed.desk, let screen = NSScreen.screens.first, let island = IslandGeometry.current(),
              island.screenFrame == screen.frame, !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            return feed.effect.configure(mode: nil, geometry: nil, agents: [], reduceMotion: false)
        }
        let mode: NotchSimulation.Mode? = desk.kind == .solar ? .solar : prefs.wallpaperIslandEffect ? .blackHole : nil
        let size = screen.frame.size
        let geometry = NotchGeometry(screen: Vec2(size.width, size.height),
                                     notchCenterX: island.centerX - screen.frame.minX,
                                     notchBottom: island.notchHeight, notchWidth: island.notchWidth,
                                     menu: Vec2(menuSize.width, menuSize.height))
        let renderer = SceneRenderers.renderer(for: desk.kind)
        let agents = desk.inhabitants.map { inhabitant in
            let spot = renderer.spot(for: inhabitant, in: desk)
            return NotchAgent(id: inhabitant.id, home: Vec2(spot.x * size.width, spot.y * size.height),
                              urgency: NotchAgent.urgency(of: inhabitant.mood))
        }
        feed.effect.configure(mode: mode, geometry: geometry, agents: agents,
                              reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
```

In `refresh()`, after `feed.desk = desk`, add `configureEffect()`.

In `updateMotion()`, add at the end:

```swift
        // Low Power Mode or Reduce Motion switched mid-effect: set it up again at once.
        configureEffect()
        if islandOpen { feed.effect.setOpen(true) }
```

In `turnOff()`, add `feed.effect.configure(mode: nil, geometry: nil, agents: [], reduceMotion: false)`.

In `Sources/AmbientApp/AppDelegate.swift`, after `self.wallpaper = wallpaper`, add:

```swift
        island?.onMenuChange = { [weak wallpaper] open, menu in wallpaper?.islandChanged(open: open, menu: menu) }
```

- [ ] **Step 8: Build and test**

Run: `swift build 2>&1 | tail -20 && swift test 2>&1 | tail -5`
Expected: a clean build with no new warnings, and every test passing.

- [ ] **Step 9: Offscreen renders of both effects**

Extend the harness in `.superpowers/sdd/2026-09-29-notch-effects/harness`:
- add `NotchEffect.swift`, `NotchEffectDrawing.swift` and `SolarScene.swift` to `sync.sh`;
- write a `render-effect` mode that:
  - builds a `SceneState` with 4 and 10 sessions of mixed moods;
  - configures a `NotchEffectEngine` for a 1512 × 982 screen, with the notch at 756, 32 pt tall and 200 wide, and the menu at 440 × 330;
  - calls `setOpen(true)` and advances the engine to 0.6 s, 2 s and 6 s;
  - renders `SceneView(state:effect:engaged: true)` through `ImageRenderer` to PNGs;
  - draws a black 440 × 330 rounded rect at the top centre as the island menu;
  - does all of this for Sky (black hole) and Solar System, at night and by day.

Then advance to 1 s and 5 s after `setOpen(false)`.

Look at every PNG and check:
- **Black hole:** the half-disk hole sits below the notch; the disk runs along the notch line; the orbs are in orbit; the sheet bends into the well.
- **Solar:** the sun sits at the notch; six planets are on ellipses below the menu; the rest are gone into the sun.
- **Closed at 5 s:** everyone is home, in rows for Solar System.
- **Day renders:** dark ink, pale sky.

- [ ] **Step 10: Commit**

```bash
git add Sources/AmbientApp
git commit -m "feat(app): the black hole and the solar system when the island opens"
```

---

### Task 5: On the real desk, and the docs

**Files:**
- Modify: `README.md`, `CHANGELOG.md`
- Modify: any file a check below shows to be wrong

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Build and run the app in place**

Run: `./scripts/build-app.sh` (or the build command recorded in the living-wallpaper ledger), then relaunch `build/Ambient.app`.
Expected: the app launches; `log stream --predicate 'subsystem == "com.viveky259259.Ambient"'` shows no errors.

- [ ] **Step 2: Check on the desk**

With the living wallpaper on, Sky chosen, and at least four sessions running (use the demo if needed), check each of these:
1. Hover the notch until the island opens: the hole forms at the notch, agents fly into orbits, dust falls in, and the menu is in front.
2. Move away: the hole evaporates, and agents coast home and settle within about 6 s. Then check CPU in Activity Monitor: back under 3% once settled.
3. While the effect runs, CPU stays under about 25%. If it's higher, lower the dust to 120 and the sheet's sample spacing to 12 pt, and ledger that as a Ruling.
4. Pick Solar System: planets stand in rows. Open the island: the sun lights, up to six planets orbit, and the rest fall in. Close it: everyone comes back to the rows.
5. Quick hover in and out three times: nothing jumps, and there's no double flash.
6. Turn on Reduce Motion in Accessibility settings and open the island: no body moves, and the hole or sun fades in behind the menu.
7. Turn on Low Power Mode and open the island: nothing happens on the wallpaper.
8. Cover the desk with a window, open the island, uncover mid-effect: it continues without a leap.
9. Settings › Wallpaper: the Scene picker shows all five choices (four worlds and A new one each day) without clipping, and the black-hole switch is greyed out while Solar System is picked.

- [ ] **Step 3: Docs**

In `README.md`, in the living wallpaper section, add after the paragraph on the scenes:

```markdown
**When you open the island**, the wallpaper answers too. In Sky, Harbor and Garden, the notch collapses into a black
hole: your agents lift off as light and swing into orbits around it while loose dust falls in, and when the island
closes they drift home. In the fourth world, **Solar System**, your agents are planets standing in rows; open the
island and the notch lights up as the sun, and the six most urgent planets orbit it (the rest fall into the sun
until it closes). Real gravity drives both. It follows Reduce Motion, and it pauses in Low Power Mode. Turn the black hole off in
Settings › Wallpaper.
```

In `CHANGELOG.md`, under the unreleased living-wallpaper entry, add:

```markdown
- A fourth world, Solar System: agents are planets; open the island and they orbit the notch-sun.
- A black hole forms at the notch when the island opens, in Sky, Harbor and Garden (Settings › Wallpaper).
```

- [ ] **Step 4: Full suite and commit**

Run: `swift test 2>&1 | tail -3`
Expected: every test passes.

```bash
git add README.md CHANGELOG.md Sources
git commit -m "docs: notch effects"
```
