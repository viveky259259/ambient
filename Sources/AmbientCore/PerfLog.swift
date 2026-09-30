import Foundation

/// What Ambient costs the Mac, measured on the Mac and kept in memory: CPU and memory, the time spent drawing the
/// wallpaper and the notch effect, and how long hook events take to arrive. Kept as one-minute totals for a day, so
/// recording is constant time and the log stays small.
public struct PerfLog: Sendable {
    public enum FrameSource: Sendable {
        case scene, effect
    }

    public struct Frames: Equatable, Sendable {
        public var frames = 0
        public var averageMs = 0.0
        /// 0…1: frames that took longer than a 60 fps budget.
        public var slowShare = 0.0
    }

    public struct Hooks: Equatable, Sendable {
        public var events = 0
        public var medianMs = 0.0
        public var p95Ms = 0.0
        public var maxMs = 0.0
    }

    public struct Summary: Equatable, Sendable {
        public var cpuAverage = 0.0
        public var cpuPeak = 0.0
        public var memoryNowMB = 0.0
        public var memoryPeakMB = 0.0
        public var scene = Frames()
        public var effect = Frames()
        public var hooks = Hooks()
    }

    public static let maxMinutes = 24 * 60
    /// A frame slower than this missed a 60 fps display's budget.
    public static let slowFrameMs = 1000.0 / 60

    private struct FrameTotals {
        var count = 0
        var totalMs = 0.0
        var slow = 0
    }

    private struct Minute {
        let key: Int
        var cpuTotal = 0.0
        var cpuCount = 0
        var cpuPeak = 0.0
        var memoryPeak = 0.0
        var memoryLast = 0.0
        var scene = FrameTotals()
        var effect = FrameTotals()
        /// Hook latencies, capped so a flood of events can't grow a minute without bound.
        var hookMs: [Double] = []
        var hookCount = 0
        var hookMax = 0.0
    }

    private static let hookSamplesPerMinute = 500
    private var minutes: [Minute] = []

    public init() {}

    public var minuteCount: Int { minutes.count }

    public mutating func recordSample(cpu: Double, memoryMB: Double, at date: Date) {
        update(at: date) { m in
            m.cpuTotal += cpu
            m.cpuCount += 1
            m.cpuPeak = max(m.cpuPeak, cpu)
            m.memoryPeak = max(m.memoryPeak, memoryMB)
            m.memoryLast = memoryMB
        }
    }

    public mutating func recordFrame(ms: Double, source: FrameSource, at date: Date) {
        update(at: date) { m in
            switch source {
            case .scene: Self.add(ms, to: &m.scene)
            case .effect: Self.add(ms, to: &m.effect)
            }
        }
    }

    public mutating func recordHookLatency(ms: Double, at date: Date) {
        update(at: date) { m in
            m.hookCount += 1
            m.hookMax = max(m.hookMax, ms)
            if m.hookMs.count < Self.hookSamplesPerMinute { m.hookMs.append(ms) }
        }
    }

    /// Totals over the last `window` seconds up to `now`.
    public func summary(over window: TimeInterval, now: Date) -> Summary {
        let newest = Self.key(now), oldest = newest - max(1, Int((window / 60).rounded(.up))) + 1
        let recent = minutes.filter { $0.key >= oldest && $0.key <= newest }
        var s = Summary()
        let cpuCount = recent.reduce(0) { $0 + $1.cpuCount }
        if cpuCount > 0 { s.cpuAverage = recent.reduce(0) { $0 + $1.cpuTotal } / Double(cpuCount) }
        s.cpuPeak = recent.map(\.cpuPeak).max() ?? 0
        s.memoryPeakMB = recent.map(\.memoryPeak).max() ?? 0
        s.memoryNowMB = recent.last(where: { $0.cpuCount > 0 })?.memoryLast ?? 0
        s.scene = Self.frames(recent.map(\.scene))
        s.effect = Self.frames(recent.map(\.effect))
        let latencies = recent.flatMap(\.hookMs).sorted()
        s.hooks.events = recent.reduce(0) { $0 + $1.hookCount }
        s.hooks.maxMs = recent.map(\.hookMax).max() ?? 0
        s.hooks.medianMs = Self.percentile(latencies, 0.5)
        s.hooks.p95Ms = Self.percentile(latencies, 0.95)
        return s
    }

    /// A plain-text report for a bug report: the last hour and the last day.
    public func report(now: Date, version: String, system: String) -> String {
        let stamp = ISO8601DateFormatter().string(from: now)
        var lines = ["# Ambient performance", "", "Ambient \(version) · \(system) · \(stamp)",
                     "Measured on this Mac while Ambient ran; nothing was sent anywhere."]
        for (title, window) in [("Last hour", 3_600.0), ("Last 24 hours", 86_400.0)] {
            let s = summary(over: window, now: now)
            lines += ["", "## \(title)",
                      "- CPU: \(Self.one(s.cpuAverage))% average, \(Self.one(s.cpuPeak))% peak",
                      "- Memory: \(Int(s.memoryNowMB.rounded())) MB now, \(Int(s.memoryPeakMB.rounded())) MB peak",
                      "- Wallpaper: \(Self.frameLine(s.scene))",
                      "- Notch effect: \(Self.frameLine(s.effect))",
                      "- Hooks: \(s.hooks.events) events, \(Int(s.hooks.medianMs.rounded())) ms median, "
                          + "\(Int(s.hooks.p95Ms.rounded())) ms p95, \(Int(s.hooks.maxMs.rounded())) ms max"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Pieces

    private mutating func update(at date: Date, _ change: (inout Minute) -> Void) {
        let key = Self.key(date)
        if let i = minutes.lastIndex(where: { $0.key == key }) {
            change(&minutes[i])
            return
        }
        var minute = Minute(key: key)
        change(&minute)
        // Minutes arrive in order in practice; a late one still lands in its place.
        let at = minutes.lastIndex(where: { $0.key < key }).map { $0 + 1 } ?? 0
        minutes.insert(minute, at: at)
        let newest = minutes.last?.key ?? key
        minutes.removeAll { $0.key <= newest - Self.maxMinutes }
    }

    private static func key(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    private static func add(_ ms: Double, to totals: inout FrameTotals) {
        totals.count += 1
        totals.totalMs += ms
        if ms > slowFrameMs { totals.slow += 1 }
    }

    private static func frames(_ totals: [FrameTotals]) -> Frames {
        let count = totals.reduce(0) { $0 + $1.count }
        guard count > 0 else { return Frames() }
        return Frames(frames: count, averageMs: totals.reduce(0) { $0 + $1.totalMs } / Double(count),
                      slowShare: Double(totals.reduce(0) { $0 + $1.slow }) / Double(count))
    }

    /// Nearest-rank percentile.
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count, max(1, rank)) - 1]
    }

    private static func one(_ x: Double) -> String { String(format: "%.1f", x) }

    private static func frameLine(_ f: Frames) -> String {
        "\(f.frames) frames, \(one(f.averageMs)) ms average draw, \(Int((f.slowShare * 100).rounded()))% slow"
    }
}
