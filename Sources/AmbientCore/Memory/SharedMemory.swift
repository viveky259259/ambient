import Foundation

/// Working memory as the app runs it: the store, its file and the shared files, on a queue of their own. Agents
/// wait on their requests, so a main thread busy drawing the UI mustn't be what answers them.
public final class SharedMemory: @unchecked Sendable {
    /// How often unreferenced copies are deleted, and how old they must be first.
    public static let collectInterval: TimeInterval = 300

    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.memory", qos: .userInitiated)
    private let store = MemoryStore()
    private let url: URL?
    private let blobs: MemoryBlobStore?
    private let saveDelay: TimeInterval
    private var saveWork: DispatchWorkItem?
    private var nextCollect = Date.distantPast

    public init(url: URL?, blobs: MemoryBlobStore?, saveDelay: TimeInterval = 1) {
        self.url = url
        self.blobs = blobs
        self.saveDelay = saveDelay
    }

    /// Loads what was saved, without what expired meanwhile.
    public func load(now: Date = Date(), isAlive: @escaping @Sendable (Int32) -> Bool = SessionStore.processExists) {
        queue.sync {
            guard let url else { return }
            if let saved = MemoryFile.load(from: url) {
                store.load(saved)
            } else {
                // A file this version can't read: its shared files aren't abandoned, and MemoryFile.save leaves it
                // alone, so what's shared until then lasts until Ambient quits.
                nextCollect = .distantFuture
            }
            if !store.sweep(now: now, isAlive: isAlive).isEmpty { scheduleSave() }
        }
    }

    /// Answers `ambient memory` and the memory tools of `ambient mcp`, on the caller's thread. `sessions` tells
    /// who's writing.
    public func answer(_ request: MemoryRequest, sessions: [Session], now: Date = Date()) -> MemoryReply {
        queue.sync {
            let revision = store.revision
            let reply = store.answer(request, sessions: sessions, blobs: blobs, now: now)
            if store.revision != revision { scheduleSave() }
            return reply
        }
    }

    /// Drops what a session kept only for itself, when it says it ended.
    public func sessionEnded(_ sessionID: String) {
        queue.async { [self] in
            if !store.sessionEnded(sessionID).isEmpty { scheduleSave() }
        }
    }

    /// Call every few seconds: drops expired entries and those of agents that exited, and now and then deletes
    /// shared files nothing refers to.
    public func sweep(now: Date = Date(), isAlive: @escaping @Sendable (Int32) -> Bool = SessionStore.processExists) {
        queue.async { [self] in
            if !store.sweep(now: now, isAlive: isAlive).isEmpty { scheduleSave() }
            guard let blobs, now >= nextCollect else { return }
            // On a timer, not after saves: a copy forgotten within the grace period would otherwise wait for the
            // next change.
            nextCollect = now.addingTimeInterval(Self.collectInterval)
            let keep = store.blobs
            DispatchQueue.global(qos: .utility).async {
                blobs.collect(keeping: keep, changedBefore: now.addingTimeInterval(-Self.collectInterval))
            }
        }
    }

    /// Saves at once, e.g. when quitting.
    public func saveNow() {
        queue.sync {
            saveWork?.cancel()
            save()
        }
    }

    /// Newest first.
    public var entries: [MemoryEntry] { queue.sync { store.entries } }

    /// Saves shortly after changes settle. Only on `queue`.
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [self] in save() }
        saveWork = work
        queue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    private func save() {
        if let url { try? MemoryFile.save(store.entries, to: url) }
    }
}
