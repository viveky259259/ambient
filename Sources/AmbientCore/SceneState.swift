import Foundation

/// Where a scene is drawn. The lock screen has its own clock and is readable by anyone nearby.
public enum SceneSurface: Sendable {
    case desk, lock
}

/// The next event today, from the user's calendar.
public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let start: Date

    public init(title: String, start: Date) {
        self.title = title
        self.start = start
    }
}

/// One session, as a scene draws it.
public struct SceneInhabitant: Identifiable, Equatable, Sendable {
    public let id: String
    public let agent: AgentKind
    /// Drives the glow. Follows acknowledgement, like the island and the Dock glow.
    public let mood: Mood
    /// 0...1: how much the current turn has done, from its tool count.
    public let busyness: Double
    /// A stable spot, `0..<SceneLayout.slotCount`.
    public let slot: Int
    /// "Claude · Needs you · 2m"
    public let headline: String
    /// "Wallpaper that follows agents · ambient-notification"
    public let place: String
    /// Free text: the tool hint, prompt, summary or error. Nil on the lock screen unless allowed.
    public let detail: String?
}

/// "612 tools": a number and what it counts.
public struct StoryItem: Equatable, Sendable {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// "10:42  Gemini finished · docs"
public struct TimelineLine: Equatable, Sendable {
    public let time: String
    public let text: String

    public init(time: String, text: String) {
        self.time = time
        self.text = text
    }
}

/// Everything a scene draws, as data. Built once per change and once a minute.
public struct SceneState: Equatable, Sendable {
    public static let maxInhabitants = 8
    public static let timelineLength = 4

    public let kind: SceneKind
    public let surface: SceneSurface
    public let light: DayLight
    public let now: Date
    /// Most urgent first.
    public let inhabitants: [SceneInhabitant]
    /// Sessions beyond `maxInhabitants`.
    public let overflow: Int
    public let marks: [DayMark]
    /// Nil on the lock screen, which draws its own clock and date.
    public let clock: String?
    public let date: String?
    public let nextEvent: String?
    public let story: [StoryItem]
    public let timeline: [TimelineLine]

    public static func make(sessions: [Session], day: DayLog, now: Date, kind: SceneKind, surface: SceneSurface,
                            lockMessages: Bool = false, nextEvent: CalendarEvent? = nil,
                            keeping previousSlots: [String: Int] = [:],
                            calendar: Calendar = .current, locale: Locale = .current) -> SceneState {
        let freeText = surface == .desk || lockMessages
        let ordered = sessions.sorted {
            if $0.mood != $1.mood { return $0.mood > $1.mood }
            if $0.lastEventAt != $1.lastEventAt { return $0.lastEventAt > $1.lastEventAt }
            return $0.id < $1.id
        }
        let shown = Array(ordered.prefix(maxInhabitants))
        let slots = SceneLayout.slots(for: shown.map(\.id), keeping: previousSlots)
        let time = formatter("jmm", calendar: calendar, locale: locale)
        return SceneState(
            kind: kind,
            surface: surface,
            light: DayLight.at(now, calendar: calendar),
            now: now,
            inhabitants: shown.map { inhabitant($0, slot: slots[$0.id] ?? 0, now: now, freeText: freeText) },
            overflow: ordered.count - shown.count,
            marks: day.marks,
            clock: surface == .desk ? time.string(from: now) : nil,
            date: surface == .desk ? formatter("EEEEdMMMM", calendar: calendar, locale: locale).string(from: now) : nil,
            nextEvent: nextEvent.map { event in
                let start = time.string(from: event.start)
                return freeText ? "\(Trim.truncate(event.title, max: 40)) at \(start)" : "Next event at \(start)"
            },
            story: story(day, sessions: sessions, now: now),
            timeline: day.moments.prefix(timelineLength).map { line($0, time: time) })
    }

    /// The world without inhabitants or text, for displays other than the main one and for thumbnails.
    public func scenery() -> SceneState {
        SceneState(kind: kind, surface: surface, light: light, now: now, inhabitants: [], overflow: 0, marks: [],
                   clock: nil, date: nil, nextEvent: nil, story: [], timeline: [])
    }

    /// 0 with no tools, 1 at 64 and beyond, on a log scale so the first few tools show.
    static func busyness(tools: Int) -> Double {
        min(1, log2(1 + Double(max(0, tools))) / log2(65))
    }

    private static func inhabitant(_ s: Session, slot: Int, now: Date, freeText: Bool) -> SceneInhabitant {
        var headline = "\(s.agent.displayName) · \(Describe.shortActivity(s.activity))"
        if let clock = Describe.clock(s, now: now, compact: true) { headline += " · \(clock)" }
        // Short enough that a label never reaches past about a quarter of the screen.
        var place = Trim.truncate(Describe.title(s), max: 36)
        if let project = Describe.place(s) { place += " · \(Trim.truncate(project, max: 24))" }
        return SceneInhabitant(id: s.id, agent: s.agent, mood: s.mood, busyness: busyness(tools: s.toolCount),
                               slot: slot, headline: headline, place: place,
                               detail: freeText ? detail(s.activity) : nil)
    }

    private static func detail(_ activity: Activity) -> String? {
        switch activity {
        case let .tool(_, detail): Trim.clean(detail, max: 56)
        case let .waiting(_, message): Trim.clean(message, max: 56)
        case let .done(summary): Trim.clean(summary, max: 56)
        case let .error(message): Trim.clean(message, max: 56)
        case .idle, .thinking, .compacting: nil
        }
    }

    private static func story(_ day: DayLog, sessions: [Session], now: Date) -> [StoryItem] {
        func count(_ n: Int, _ one: String, _ many: String) -> StoryItem { StoryItem(value: "\(n)", label: n == 1 ? one : many) }
        var items: [StoryItem] = []
        let agentTime = day.agentTime(live: sessions, now: now)
        if agentTime >= 60 { items.append(StoryItem(value: Describe.duration(agentTime), label: "of agent time")) }
        if day.tools > 0 { items.append(count(day.tools, "tool", "tools")) }
        if day.turnsDone > 0 { items.append(count(day.turnsDone, "turn done", "turns done")) }
        if day.turnsFailed > 0 { items.append(StoryItem(value: "\(day.turnsFailed)", label: "failed")) }
        if day.neededYou > 0 { items.append(count(day.neededYou, "call for you", "calls for you")) }
        if !day.projects.isEmpty { items.append(count(day.projects.count, "project", "projects")) }
        if day.longestRun >= 60 { items.append(StoryItem(value: Describe.duration(day.longestRun), label: "longest run")) }
        return items
    }

    private static func line(_ moment: DayMoment, time: DateFormatter) -> TimelineLine {
        let verb = switch moment.kind {
        case .neededYou: "needed you"
        case .done: "finished"
        case .failed: "failed"
        }
        return TimelineLine(time: time.string(from: moment.at),
                            text: "\(moment.agent.displayName) \(verb) · \(Trim.truncate(moment.place, max: 40))")
    }

    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}

/// Stable spots for inhabitants: a session keeps its spot for as long as it lives.
public enum SceneLayout {
    public static let slotCount = 12

    /// Spots by session id. Sessions that already had one keep it; new ones, in id order, take the first free spot.
    /// Scenes list their best spots first, so a handful of sessions always gets those.
    public static func slots(for ids: [String], keeping previous: [String: Int] = [:]) -> [String: Int] {
        var result: [String: Int] = [:]
        var taken = Set<Int>()
        for id in ids {
            if let slot = previous[id], (0..<slotCount).contains(slot), !taken.contains(slot) {
                result[id] = slot
                taken.insert(slot)
            }
        }
        for id in ids.sorted() where result[id] == nil {
            guard let slot = (0..<slotCount).first(where: { !taken.contains($0) }) else { break }
            result[id] = slot
            taken.insert(slot)
        }
        return result
    }
}
