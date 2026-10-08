import Foundation

/// What the pet acts out: the most urgent session's state, or sleep when nothing needs showing.
public enum PetPose: CaseIterable, Equatable, Sendable {
    case sleeping, working, waiting, done, error
}

/// A short animation the pet plays when clicked, or when a session starts to need you.
public enum PetReaction: Hashable, Sendable {
    /// Jumps awake.
    case wake
    /// A small hop, back to work.
    case hop
    /// Hops twice to get your attention.
    case wave
    /// A high jump with a spin.
    case cheer
    /// Shakes its head.
    case shake
}

/// What the desktop pet shows. It carries only what's worth your attention: idle sessions and results you've
/// already seen are left out, so with nothing to show the pet sleeps.
public enum PetPolicy {
    public static let maxListed = 5
    /// The peek's rows are a third the height of the list's, so it holds more.
    public static let maxPeeked = 8

    /// Sessions worth showing, most urgent first (the store's order).
    public static func relevant(_ sessions: [Session]) -> [Session] {
        sessions.filter { $0.mood != .idle }
    }

    public static func pose(_ sessions: [Session]) -> PetPose {
        switch relevant(sessions).first?.mood {
        case nil, .idle: .sleeping
        case .working: .working
        case .waiting: .waiting
        case .done: .done
        case .error: .error
        }
    }

    public static func reaction(to pose: PetPose) -> PetReaction {
        switch pose {
        case .sleeping: .wake
        case .working: .hop
        case .waiting: .wave
        case .done: .cheer
        case .error: .shake
        }
    }

    /// Relevant sessions grouped by urgency, alphabetically within a group. Unlike the store's order, which
    /// follows the latest event, this one holds still while agents work, so nothing shuffles under the pointer.
    public static func ordered(_ sessions: [Session]) -> [Session] {
        relevant(sessions).sorted {
            if $0.mood != $1.mood { return $0.mood > $1.mood }
            let a = Describe.title($0).lowercased(), b = Describe.title($1).lowercased()
            return a != b ? a < b : $0.id < $1.id
        }
    }

    /// The session in the bubble. It stays put while others of the same urgency come and go, and gives way
    /// only to something more urgent, or when it no longer matters.
    public static func primary(_ sessions: [Session], current: String?) -> Session? {
        let all = relevant(sessions)
        guard let top = all.first else { return nil }
        if let current, let kept = all.first(where: { $0.id == current }), kept.mood >= top.mood { return kept }
        return top
    }

    /// The sessions the open list shows, and how many more there are.
    public static func listed(_ sessions: [Session]) -> (shown: [Session], more: Int) {
        let all = ordered(sessions)
        return (Array(all.prefix(maxListed)), max(0, all.count - maxListed))
    }

    /// The bubble's note about the other sessions: loud only when one of them needs you too.
    public static func badge(_ sessions: [Session], primary: String?) -> String? {
        let others = relevant(sessions).filter { $0.id != primary }
        let waiting = others.filter { $0.mood == .waiting }.count
        if waiting > 0 { return "+\(waiting) needs you" }
        return others.isEmpty ? nil : "+\(others.count)"
    }

    /// Prompts waiting for you that you haven't looked at.
    public static func waitingCount(_ sessions: [Session]) -> Int {
        relevant(sessions).filter { $0.mood == .waiting }.count
    }

    /// Several sessions are worth showing: the pet adds pips and the list a summary.
    public static func isMulti(_ sessions: [Session]) -> Bool {
        relevant(sessions).count >= 2
    }

    /// "Needs you 2 · Failed 1 · Done 1 · Working 2", for the foot of the list; nil for a single session.
    public static func summary(_ sessions: [Session]) -> String? {
        guard isMulti(sessions) else { return nil }
        let all = relevant(sessions)
        let parts: [(String, Mood)] = [("Needs you", .waiting), ("Failed", .error), ("Done", .done), ("Working", .working)]
        return parts.compactMap { name, mood in
            let n = all.filter { $0.mood == mood }.count
            return n > 0 ? "\(name) \(n)" : nil
        }.joined(separator: " · ")
    }

    /// What clicking the pet shows: every session worth showing, titles only, most urgent first.
    public static func peek(_ sessions: [Session]) -> (shown: [Session], more: Int) {
        let all = ordered(sessions)
        return (Array(all.prefix(maxPeeked)), max(0, all.count - maxPeeked))
    }

    /// The markers under the pet, one per session, when there are several.
    public static func pips(_ sessions: [Session]) -> (shown: [Session], more: Int) {
        guard isMulti(sessions) else { return ([], 0) }
        let all = ordered(sessions)
        return (Array(all.prefix(maxListed)), max(0, all.count - maxListed))
    }

    /// The reaction that announces a change on its own: the moments the island blooms for.
    public static func announce(_ t: SessionChange, quiet: Bool) -> PetReaction? {
        guard IslandPolicy.bloomDuration(for: t, quiet: quiet) != nil else { return nil }
        return reaction(to: pose([t.session]))
    }
}

/// Keeps unprompted reactions from piling up: when several sessions finish at once the pet cheers once. Within the
/// quiet window only a more urgent reaction gets through (needs you › failed › done).
public struct PetReactionGate: Sendable {
    public static let window: TimeInterval = 4
    private var last: (reaction: PetReaction, at: Date)?

    public init() {}

    public mutating func allow(_ reaction: PetReaction, at now: Date) -> Bool {
        if let last, now.timeIntervalSince(last.at) < Self.window, Self.rank(reaction) <= Self.rank(last.reaction) {
            return false
        }
        last = (reaction, now)
        return true
    }

    private static func rank(_ r: PetReaction) -> Int {
        switch r {
        case .wave: 3
        case .shake: 2
        case .cheer: 1
        case .hop, .wake: 0
        }
    }
}
