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
    /// Bodies at rest (everything settled, or Reduce Motion) move straight to their new homes; an agent that joins
    /// an open black hole gets the birth's sideways speed, so it swings into orbit instead of falling through.
    public mutating func setAgents(_ agents: [NotchAgent]) {
        let existing = Dictionary(bodies.filter(\.isAgent).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resting = reduceMotion || isSettled
        var seen = Set<String>()
        var agentBodies: [Body] = []
        for agent in agents where seen.insert(agent.id).inserted {
            var body = existing[agent.id] ?? Body(id: agent.id, isAgent: true, brightness: 1, home: agent.home)
            body.home = agent.home
            if resting {
                body.position = agent.home
                body.velocity = .zero
            } else if existing[agent.id] == nil, mode == .blackHole, born, gravity > 0 {
                Self.kick(&body, gm: gravity, geometry: geometry, spread: 0)
            }
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
        guard mode == .blackHole, isOpen, !reduceMotion, sinceOpen < 1.6 else { return nil }
        return sinceOpen * geometry.screen.y * 1.1
    }

    /// 0…1: the flash as the notch collapses.
    public var birthFlash: Double {
        mode == .blackHole && isOpen && !reduceMotion && sinceOpen < 0.5 ? 1 - sinceOpen / 0.5 : 0
    }

    /// 0…1: the faint flash as the hole evaporates.
    public var evaporation: Double {
        mode == .blackHole && !isOpen && presenceAtClose > 0 && sinceClose < 0.45 ? 1 - sinceClose / 0.45 : 0
    }

    /// How strongly the effect's own dust shows. The black hole's dust shows fully while open and fades over 2.5 s
    /// after closing; the asteroid belt comes and goes with the sun, so it's gone by the time the system settles.
    public var dustAlpha: Double {
        switch mode {
        case .blackHole: isOpen ? 1 : max(0, 1 - sinceClose / 2.5)
        case .solar: presence
        }
    }

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

    /// The birth's sideways speed: a Kepler ellipse released at its far point. Agents' closest pass stays well
    /// outside the hole; dust gets random ones (`spread`, 0…1).
    private static func kick(_ body: inout Body, gm: Double, geometry: NotchGeometry, spread: Double) {
        let d = body.position - geometry.center, r = max(1, d.length)
        let peri = body.isAgent ? max(geometry.radius * 1.9, r * 0.42) : r * (0.05 + spread * 0.5)
        let speed = (2 * gm * peri / (r * (r + peri))).squareRoot()
        body.velocity = body.velocity + Vec2(-d.y / r, d.x / r) * speed
    }

    private mutating func integrateBlackHole(_ h: Double) {
        let c = geometry.center, gm = gravity, holeRadius = radius, height = geometry.screen.y
        if gm > 0, !born {
            // The birth: every body gets the sideways speed of a Kepler ellipse released at its far point.
            // Agents' closest pass stays well outside the hole; dust gets random ones, so some falls in.
            born = true
            for i in bodies.indices where !bodies[i].absorbed {
                let spread = bodies[i].isAgent ? 0 : rng.next()
                Self.kick(&bodies[i], gm: gm, geometry: geometry, spread: spread)
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
struct SplitMix: Sendable {
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
