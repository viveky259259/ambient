import AmbientCore
import Foundation
import os

/// Keeps one `RemoteLink` per paired machine. `machines.json` is the allowlist: the `ambient` CLI edits it and this
/// follows, so pairing never needs the socket. Nothing here ever listens: every link dials out.
final class RemoteCoordinator {
    private let paths: AmbientPaths
    private let model: AppModel
    private let voice: VoiceSyncController
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "remote")
    private let bundledShim = RemoteShim.bundledURL().flatMap { try? RemoteShim(url: $0) }
    /// Links stop on this queue: stopping waits for the thread, and the main thread is what that thread feeds.
    private let stopping = DispatchQueue(label: "com.viveky259259.Ambient.remote.stop", qos: .utility)
    private var links: [String: RemoteLink] = [:]
    private var machines: [Machine] = []
    private var machinesChangedAt: Date?
    private var pollTimer: Timer?
    private var limits: RemoteAuditThrottle

    init(paths: AmbientPaths, model: AppModel, voice: VoiceSyncController) {
        self.paths = paths
        self.model = model
        self.voice = voice
        limits = RemoteAuditThrottle(audit: paths.remoteAudit)
    }

    func start() {
        reload(force: true)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reload() }
        pollTimer?.tolerance = 1
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        let running = Array(links.values)
        links = [:]
        // Quitting: end the transports now rather than leave them to notice. Stopping takes moments.
        let done = DispatchGroup()
        for link in running {
            done.enter()
            stopping.async {
                link.stop()
                done.leave()
            }
        }
        _ = done.wait(timeout: .now() + 2)
    }

    /// Unpairs a machine from Settings, as `ambient remote remove` does. False when it's still paired.
    @discardableResult
    func remove(_ id: String) -> Bool {
        let list = MachineFile.load(from: paths.machinesFile).filter { $0.id != id }
        do {
            try MachineFile.save(list, to: paths.machinesFile)
        } catch {
            log.error("Couldn't update the machine list: \(error.localizedDescription)")
            return false
        }
        paths.remoteAudit.append(.init(action: .unpaired, machine: id))
        voice.forget(machine: id)
        reload(force: true)
        return true
    }

    /// Unpairs it and deletes everything it left on this Mac, as `ambient remote purge` does. Nothing goes while it's
    /// still paired, or its link would bring the voices in its outbox back.
    func purge(_ id: String) {
        guard remove(id) else { return }
        model.purge(machine: id)
        voice.purge(machine: id)
        paths.remoteAudit.append(.init(action: .purged, machine: id))
    }

    func policyChanged(_ detail: String) {
        paths.remoteAudit.append(.init(action: .policyChanged, machine: "*", detail: detail))
    }

    private func reload(force: Bool = false) {
        for id in RemotePurge.pendingPurges(paths: paths) {
            model.purge(machine: id)
            voice.purge(machine: id)
            RemotePurge.clearPurge(id, paths: paths)
        }
        let changedAt = (try? FileManager.default.attributesOfItem(atPath: paths.machinesFile.path))?[.modificationDate] as? Date
        guard force || changedAt != machinesChangedAt else { return }
        machinesChangedAt = changedAt

        let next = MachineFile.load(from: paths.machinesFile)
        let previous = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
        machines = next
        model.keepMachines(next)
        for (id, link) in links where !next.contains(where: { $0.id == id }) {
            links[id] = nil
            // Unpaired from the command line: the app's copy of the library forgets it too, or it'd save the cursor back.
            voice.forget(machine: id)
            stopping.async { link.stop() }
        }
        for machine in next where previous[machine.id] != machine || links[machine.id] == nil {
            if let link = links[machine.id] {
                links[machine.id] = nil
                // A new link can't start until the old one has stopped, or two would follow the same spool.
                stopping.async { [weak self] in
                    link.stop()
                    DispatchQueue.main.async { self?.follow(machine) }
                }
            } else {
                follow(machine)
            }
        }
    }

    private func follow(_ machine: Machine) {
        guard machines.contains(machine), links[machine.id] == nil else { return }
        let coordinator = MainThreadBox(self)
        let model = MainThreadBox(self.model)
        let ref = machine.ref
        let shimVersion = bundledShim?.version
        let voice = MainThreadBox(self.voice)
        let receiver = VoiceReceiver(hub: self.voice.hub, cursor: self.voice.cursor(for: machine.id),
                                     known: self.voice.received(from: machine.id)) { events, cursor in
            DispatchQueue.main.async {
                // A link that's stopping can still hand over a voice. Once its machine is unpaired that's dropped, as
                // its sessions are, or a purged voice would come back with its cursor.
                guard coordinator.value.machines.contains(where: { $0.id == ref.id }) else { return }
                voice.value.receive(events, cursor: cursor, from: ref)
            }
        }
        let link = RemoteLink(
            machine: machine, cursor: self.model.remoteCursor(machine.id), audit: paths.remoteAudit, voice: receiver,
            deliver: { batch, cursor, applied in
                DispatchQueue.main.async {
                    coordinator.value.apply(batch, cursor: cursor, from: ref)
                    applied()
                }
            },
            report: { health, hello in
                DispatchQueue.main.async {
                    model.value.setRemoteHealth(health, machine: machine, hello: hello,
                                                updateAvailable: hello.map { $0.shim != shimVersion } ?? false)
                }
            })
        links[machine.id] = link
        link.start()
    }

    private func apply(_ batch: [RemoteDelivery], cursor: RemoteCursor, from machine: MachineRef) {
        let refused = model.applyRemote(batch, cursor: cursor, from: machine)
        if refused > 0 { limits.record(.sessionLimit, machine: machine.id, count: refused, now: Date()) }
    }
}

/// Carries a main-thread object through a background closure that only hops back to main to use it.
private struct MainThreadBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
