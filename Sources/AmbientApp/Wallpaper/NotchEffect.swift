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
    /// Label lines cut to fit a planet's column, so they're measured once rather than every frame.
    var fittedLines: [String: String] = [:]

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
        guard let sim = simulation else { return }
        if sim.isOpen != open {
            simulation?.setOpen(open)
            lastDate = nil
        }
        if open, !engaged { engaged = true }
    }

    /// Steps the simulation to `date`. Called from the scene's life canvas, once per frame.
    func advance(to date: Date) {
        guard var sim = simulation else { return }
        // A gap longer than a quarter second is a pause (the desk was covered), not motion: pick up where it was.
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        sim.step(dt > 0.25 ? 1.0 / 60 : dt)
        lastDate = date
        simulation = sim
        let present = Set(sim.agents.map(\.id))
        if trails.keys.contains(where: { !present.contains($0) }) { trails = trails.filter { present.contains($0.key) } }
        for body in sim.agents {
            var trail = trails[body.id] ?? []
            trail.append(CGPoint(x: body.position.x, y: body.position.y))
            if trail.count > 30 { trail.removeFirst(trail.count - 30) }
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
