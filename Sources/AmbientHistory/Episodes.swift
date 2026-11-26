import Foundation

/// One request in a chat and everything done about it, up to the next request.
public struct Episode: Equatable, Sendable {
    /// 1-based.
    public var n: Int
    public var firstEvent: Int
    public var lastEvent: Int
    public var at: Date?
    public var request: String
    /// Files it changed, in the order they were first changed.
    public var changed: [String]
    /// Commits whose command ran in it.
    public var made: [String]
}

public enum Episodes {
    /// Splits a chat where the person spoke. Two messages in a row with nothing done between them are one request.
    public static func split(_ record: ChatRecord) -> [Episode] {
        var episodes: [Episode] = []
        var current: Episode?
        var acted = false
        func close(_ episode: Episode?, at last: Int) {
            guard var episode else { return }
            episode.lastEvent = last
            episodes.append(episode)
        }
        for event in record.events {
            let isRequest = event.kind == .user && event.actor == nil
            if isRequest, current != nil, !acted {
                current?.request += "\n\n" + event.text
                continue
            }
            if isRequest || current == nil {
                close(current, at: event.n - 1)
                // A chat another session started opens with that session's brief, not with something a person typed
                // here. The brief is what was asked, so it stands as the request.
                let brief = event.kind == .system && event.actor == nil && !isNotice(event.text) ? event.text : ""
                current = Episode(n: episodes.count + 1, firstEvent: event.n, lastEvent: event.n, at: event.at,
                                  request: isRequest ? event.text : brief, changed: [], made: [])
                acted = !isRequest
                continue
            }
            acted = true
        }
        close(current, at: record.events.last?.n ?? 0)

        for index in episodes.indices {
            let range = episodes[index].firstEvent...episodes[index].lastEvent
            var seen = Set<String>()
            for event in record.events[(range.lowerBound - 1)...(range.upperBound - 1)] {
                for touch in event.touches ?? [] where touch.how.changes && inRepository(touch.path)
                    && seen.insert(touch.path).inserted {
                    episodes[index].changed.append(touch.path)
                }
            }
            episodes[index].made = record.commits.filter { $0.event.map(range.contains) == true }.map(\.sha)
        }
        return episodes
    }

    /// True for text a harness adds about something that happened (a task finished, a check failed, a turn was cut
    /// short), as opposed to a brief that asks for work.
    static func isNotice(_ text: String) -> Bool {
        let start = text.drop { $0 == " " || $0 == "\n" }
        return start.hasPrefix("<") || start.hasPrefix("[Request interrupted") || start.hasPrefix("The app was quit")
            || start.hasPrefix("This session is being continued") || start.hasPrefix("Caveat:")
    }

    static func inRepository(_ path: String) -> Bool { !path.hasPrefix("/") && !path.hasPrefix("~") }

    /// Every file each request had to do with, once per file and request, as the strongest thing done to it.
    public static func touches(in record: ChatRecord, episodes: [Episode]) -> [PlacedTouch] {
        var placed: [PlacedTouch] = []
        for episode in episodes {
            var best: [String: PlacedTouch] = [:]
            var order: [String] = []
            for event in record.events[(episode.firstEvent - 1)...(episode.lastEvent - 1)] {
                for touch in event.touches ?? [] where inRepository(touch.path) {
                    if let existing = best[touch.path] {
                        if Capture.rank(touch.how) < Capture.rank(existing.how) {
                            best[touch.path] = PlacedTouch(path: touch.path, how: touch.how, episode: episode.n, event: event.n)
                        }
                    } else {
                        best[touch.path] = PlacedTouch(path: touch.path, how: touch.how, episode: episode.n, event: event.n)
                        order.append(touch.path)
                    }
                }
            }
            placed += order.compactMap { best[$0] }
        }
        return placed
    }

    /// The card a chat's own words give, with no model: the request, and what the agent said last about it.
    public static func card(for episode: Episode, in record: ChatRecord) -> ChangeCard {
        let events = record.events[(episode.firstEvent - 1)...(episode.lastEvent - 1)]
        // What the agent said last, before any CI notice the harness added afterwards: replies to those are about the
        // pull request's checks, not about the request.
        let own = events.prefix { !($0.kind == .system && $0.text.hasPrefix("<ci-monitor-event>")) }
        let closing = own.last { $0.kind == .agent && $0.actor == nil } ?? events.last { $0.kind == .agent && $0.actor == nil }
            ?? events.last { $0.kind == .agent }
        // A commit carries the request's work when it was made during it, or later in the chat with one of its files.
        let changed = Set(episode.changed)
        let carrying = record.commits.filter { commit in
            episode.made.contains(commit.sha)
                || ((commit.event ?? 0) >= episode.firstEvent && !changed.isDisjoint(with: commit.files))
        }.map(\.sha)
        let landed: ChangeCard.Landed = !carrying.isEmpty ? .committed : (changed.isEmpty ? .none : .uncommitted)
        var evidence = events.filter { ($0.touches ?? []).contains { $0.how.changes } }.map(\.n)
        if let closing { evidence.append(closing.n) }
        return ChangeCard(episode: episode.n, firstEvent: episode.firstEvent, lastEvent: episode.lastEvent,
                          at: episode.at, request: clip(episode.request, 800),
                          summary: clip(closing?.text ?? "", 900), files: episode.changed, commits: carrying,
                          landed: landed, evidence: Array(Set(evidence).sorted().suffix(8)), source: "extract")
    }

    /// `text` trimmed, and cut with an ellipsis when it runs past `limit`.
    public static func clip(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" : trimmed
    }
}
