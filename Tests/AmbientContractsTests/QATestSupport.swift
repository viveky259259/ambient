import Foundation
import Testing
@testable import AmbientContracts

/// Shared fixed clocks, calendars and JSON helpers for the QA suites. Nothing here reads the current time or zone.
enum QA {
    /// 2026-11-21 12:00:00 UTC.
    static let noon = Date(timeIntervalSince1970: 1_795_262_400)
    static let t0 = noon

    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static let utc = calendar("UTC")

    /// A wall-clock moment in `calendar`'s zone.
    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0,
                     in calendar: Calendar = utc) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: encode(value))
    }

    /// The value's JSON as a dictionary, to look at the wire shape.
    static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: encode(value)) as! [String: Any]
    }

    /// The value's JSON with one key replaced or removed, re-serialized: older and newer shapes of the same value.
    static func edited<T: Encodable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var dict = try object(value)
        edit(&dict)
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static let machine = MachineRef(id: "m1", label: "Studio")

    static func origin(project: String? = "api", missed: Bool = false, unreachable: Bool = false) -> RemoteOrigin {
        RemoteOrigin(machine: machine, project: project, lastSeq: 7, missed: missed, unreachable: unreachable)
    }

    static func session(_ agent: AgentKind = .claude, id: String = "s1", activity: Activity = .idle,
                        acknowledged: Bool = false, origin: RemoteOrigin? = nil, cwd: String? = nil,
                        title: String? = nil, at: Date = t0) -> Session {
        var s = Session(agent: agent, sessionId: id, at: at, origin: origin)
        s.activity = activity
        s.acknowledged = acknowledged
        s.cwd = cwd
        s.title = title
        return s
    }
}
