import Foundation
import Testing
@testable import AmbientBase

/// Aligned to a minute boundary so offsets map to predictable minutes.
private let t0 = Date(timeIntervalSince1970: 1_790_700_000 - 1_790_700_000.truncatingRemainder(dividingBy: 60))

private func at(minute: Double, second: Double = 0) -> Date { t0.addingTimeInterval(minute * 60 + second) }

@Suite("PerfLog (QA)")
struct QAPerfLogTests {
    @Test func newLogIsEmpty() {
        #expect(PerfLog().summary(over: 86_400, now: t0) == PerfLog.Summary())
        #expect(PerfLog.maxMinutes == 1_440)
    }

    @Test func samplesInOneMinuteShareABucket() {
        var log = PerfLog()
        log.recordSample(cpu: 2, memoryMB: 1, at: at(minute: 0, second: 0))
        log.recordSample(cpu: 4, memoryMB: 1, at: at(minute: 0, second: 59.9))
        log.recordSample(cpu: 100, memoryMB: 1, at: at(minute: 1))
        // A one-minute window at minute 0 sees both of its samples and nothing from minute 1.
        #expect(log.summary(over: 60, now: at(minute: 0, second: 30)).cpuAverage == 3)
        #expect(log.summary(over: 60, now: at(minute: 1)).cpuAverage == 100)
    }

    @Test func outOfOrderMinutesLandInPlace() {
        var log = PerfLog()
        log.recordSample(cpu: 10, memoryMB: 10, at: at(minute: 0))
        log.recordSample(cpu: 30, memoryMB: 30, at: at(minute: 2))
        log.recordSample(cpu: 20, memoryMB: 20, at: at(minute: 1))   // late arrival
        log.recordSample(cpu: 5, memoryMB: 5, at: at(minute: -5))    // older than everything
        let s = log.summary(over: 3_600, now: at(minute: 2))
        #expect(s.cpuAverage == 65.0 / 4)
        // "now" is the newest minute that had a sample, not the last one recorded.
        #expect(s.memoryNowMB == 30)
        // A late sample into an existing minute updates it rather than adding one.
        log.recordSample(cpu: 90, memoryMB: 1, at: at(minute: 1, second: 30))
        let after = log.summary(over: 3_600, now: at(minute: 2))
        #expect(after.cpuPeak == 90)
        #expect(after.cpuAverage == 155.0 / 5)
        #expect(after.memoryNowMB == 30)
    }

    @Test func memoryNowSkipsMinutesWithoutSamples() {
        var log = PerfLog()
        log.recordSample(cpu: 1, memoryMB: 77, at: at(minute: 0))
        log.recordHookLatency(ms: 3, at: at(minute: 1))
        log.recordFrame(intervalMs: 16, budgetMs: 16, source: .effect, at: at(minute: 2))
        #expect(log.summary(over: 3_600, now: at(minute: 2)).memoryNowMB == 77)
    }

    @Test func minutesAfterNowAreExcluded() {
        var log = PerfLog()
        log.recordSample(cpu: 5, memoryMB: 5, at: at(minute: 0))
        log.recordSample(cpu: 99, memoryMB: 99, at: at(minute: 10))
        let s = log.summary(over: 3_600, now: at(minute: 5))
        #expect(s.cpuPeak == 5)
        #expect(s.memoryNowMB == 5)
    }

    @Test(arguments: [(0.0, 1), (1.0, 1), (60.0, 1), (61.0, 2), (120.0, 2), (121.0, 3), (-100.0, 1)])
    func windowRoundsUpToWholeMinutes(window: TimeInterval, minutesIncluded: Int) {
        var log = PerfLog()
        for m in 0..<5 { log.recordSample(cpu: Double(m + 1), memoryMB: 1, at: at(minute: Double(m))) }
        let s = log.summary(over: window, now: at(minute: 4, second: 30))
        // The oldest included minute sets the average: minutes 4, 3, 2… have cpu 5, 4, 3…
        let included = (0..<minutesIncluded).map { 5.0 - Double($0) }
        #expect(s.cpuAverage == included.reduce(0, +) / Double(included.count), "window \(window)")
    }

    // MARK: Frames

    @Test(arguments: [0.0, -1.0, -.infinity])
    func nonPositiveIntervalsAreIgnored(interval: Double) {
        var log = PerfLog()
        log.recordFrame(intervalMs: interval, budgetMs: 16, source: .scene, at: t0)
        #expect(log.summary(over: 60, now: t0) == PerfLog.Summary())
    }

    @Test func pauseCutoffIsTheLargerOfOneSecondAndThreeBudgets() {
        var log = PerfLog()
        // Small budget: the cutoff is 1000 ms.
        log.recordFrame(intervalMs: 1_000, budgetMs: 16, source: .scene, at: t0)       // counted (late)
        log.recordFrame(intervalMs: 1_000.001, budgetMs: 16, source: .scene, at: t0)   // pause
        // Big budget: the cutoff is 3 × budget.
        log.recordFrame(intervalMs: 1_500, budgetMs: 500, source: .effect, at: t0)     // counted (exactly 3×)
        log.recordFrame(intervalMs: 1_500.1, budgetMs: 500, source: .effect, at: t0)   // pause
        let s = log.summary(over: 60, now: t0)
        #expect(s.scene.frames == 1)
        #expect(s.scene.lateShare == 1)
        #expect(s.effect.frames == 1)
        #expect(s.effect.lateShare == 1)
    }

    @Test func lateMeansMoreThanHalfAFrameLate() {
        var log = PerfLog()
        log.recordFrame(intervalMs: 150, budgetMs: 100, source: .scene, at: t0)       // exactly 1.5×: on time
        log.recordFrame(intervalMs: 150.0001, budgetMs: 100, source: .scene, at: t0)  // late
        log.recordFrame(intervalMs: 10, budgetMs: 100, source: .scene, at: t0)        // early is fine
        log.recordFrame(intervalMs: 100, budgetMs: 100, source: .scene, at: t0)
        let s = log.summary(over: 60, now: t0)
        #expect(s.scene.frames == 4)
        #expect(s.scene.lateShare == 0.25)
    }

    @Test func ignoredFramesDoNotCreateAMinute() {
        var log = PerfLog()
        log.recordFrame(intervalMs: 60_000, budgetMs: 16, source: .scene, at: t0)
        #expect(log.summary(over: 60, now: t0) == PerfLog.Summary())
    }

    @Test func sceneAndEffectAreSeparate() {
        var log = PerfLog()
        for _ in 0..<3 { log.recordFrame(intervalMs: 50, budgetMs: 50, source: .scene, at: t0) }
        for _ in 0..<5 { log.recordFrame(intervalMs: 10, budgetMs: 10, source: .effect, at: t0) }
        let s = log.summary(over: 60, now: t0)
        #expect(s.scene.frames == 3 && abs(s.scene.fps - 20) < 1e-9 && s.scene.lateShare == 0)
        #expect(s.effect.frames == 5 && abs(s.effect.fps - 100) < 1e-9 && s.effect.lateShare == 0)
    }

    @Test func framesAcrossMinutesCombine() {
        var log = PerfLog()
        log.recordFrame(intervalMs: 100, budgetMs: 100, source: .scene, at: at(minute: 0))
        log.recordFrame(intervalMs: 300, budgetMs: 100, source: .scene, at: at(minute: 1))
        let s = log.summary(over: 3_600, now: at(minute: 1))
        #expect(s.scene.frames == 2)
        #expect(abs(s.scene.fps - 5) < 1e-9)
        #expect(s.scene.lateShare == 0.5)
    }

    // MARK: Hooks

    @Test func hookSamplesAreCappedButEventsAndMaxAreNot() {
        var log = PerfLog()
        for _ in 0..<600 { log.recordHookLatency(ms: 1, at: t0) }
        log.recordHookLatency(ms: 999, at: t0)   // beyond the sample cap
        let s = log.summary(over: 60, now: t0)
        #expect(s.hooks.events == 601)
        #expect(s.hooks.maxMs == 999)
        #expect(s.hooks.p95Ms == 1)   // the 601st sample isn't kept for percentiles
        #expect(s.hooks.medianMs == 1)
    }

    @Test func hookPercentilesAcrossMinutes() {
        var log = PerfLog()
        log.recordHookLatency(ms: 30, at: at(minute: 0))
        log.recordHookLatency(ms: 10, at: at(minute: 1))
        log.recordHookLatency(ms: 20, at: at(minute: 2))
        let s = log.summary(over: 3_600, now: at(minute: 2))
        #expect(s.hooks == PerfLog.Hooks(events: 3, medianMs: 20, p95Ms: 30, maxMs: 30))
    }

    @Test func singleHookSample() {
        var log = PerfLog()
        log.recordHookLatency(ms: 7, at: t0)
        let h = log.summary(over: 60, now: t0).hooks
        #expect(h == PerfLog.Hooks(events: 1, medianMs: 7, p95Ms: 7, maxMs: 7))
    }

    // MARK: Retention

    private static let tenDays = 10 * 86_400.0

    @Test func retentionDropsMinutesADayOlderThanTheNewest() {
        var log = PerfLog()
        let last = Double(PerfLog.maxMinutes)
        log.recordSample(cpu: 99, memoryMB: 1, at: at(minute: 0))
        log.recordSample(cpu: 1, memoryMB: 1, at: at(minute: last - 1))
        #expect(log.summary(over: Self.tenDays, now: at(minute: last - 1)).cpuPeak == 99)   // still kept
        log.recordSample(cpu: 1, memoryMB: 1, at: at(minute: last))
        #expect(log.summary(over: Self.tenDays, now: at(minute: last)).cpuPeak == 1)        // minute 0 fell out
    }

    @Test func aMinuteTooOldToKeepIsDroppedImmediately() {
        var log = PerfLog()
        let late = Double(PerfLog.maxMinutes) * 2
        log.recordSample(cpu: 1, memoryMB: 1, at: at(minute: late))
        log.recordSample(cpu: 50, memoryMB: 1, at: at(minute: 0))
        #expect(log.summary(over: Self.tenDays, now: at(minute: late)).cpuPeak == 1)
    }

    @Test func aLongGapClearsEverythingOld() {
        var log = PerfLog()
        for m in 0..<100 { log.recordSample(cpu: 50, memoryMB: 1, at: at(minute: Double(m))) }
        let far = 5 * Double(PerfLog.maxMinutes)
        log.recordSample(cpu: 1, memoryMB: 1, at: at(minute: far))
        let s = log.summary(over: Self.tenDays, now: at(minute: far))
        #expect(s.cpuPeak == 1 && s.cpuAverage == 1)
    }

    // MARK: Report

    @Test func reportShapeOnAnEmptyLog() {
        let report = PerfLog().report(now: t0, version: "9.9.9", system: "macOS test")
        #expect(report.hasPrefix("# Ambient performance\n\nAmbient 9.9.9 · macOS test · "))
        #expect(report.hasSuffix("\n"))
        #expect(report.contains(ISO8601DateFormatter().string(from: t0)))
        #expect(report.contains("nothing was sent anywhere"))
        #expect(report.components(separatedBy: "- CPU: 0.0% average, 0.0% peak").count == 3)
        #expect(report.components(separatedBy: "- Memory: 0 MB now, 0 MB peak").count == 3)
        #expect(report.components(separatedBy: "0 frames, 0.0 fps, 0% late").count == 5)
        #expect(report.components(separatedBy: "- Hooks: 0 events, 0 ms median, 0 ms p95, 0 ms max").count == 3)
        #expect(report.range(of: "## Last hour")!.lowerBound < report.range(of: "## Last 24 hours")!.lowerBound)
    }

    @Test func reportSeparatesTheHourFromTheDay() {
        var log = PerfLog()
        log.recordSample(cpu: 80, memoryMB: 500, at: at(minute: 0))
        log.recordSample(cpu: 2, memoryMB: 50, at: at(minute: 300))
        log.recordFrame(intervalMs: 50, budgetMs: 25, source: .effect, at: at(minute: 300))
        let report = log.report(now: at(minute: 300), version: "1", system: "s")
        let parts = report.components(separatedBy: "## Last 24 hours")
        #expect(parts.count == 2)
        #expect(parts[0].contains("CPU: 2.0% average, 2.0% peak"))
        #expect(parts[0].contains("Memory: 50 MB now, 50 MB peak"))
        #expect(parts[0].contains("Notch effect: 1 frames, 20.0 fps, 100% late"))
        #expect(parts[1].contains("CPU: 41.0% average, 80.0% peak"))
        #expect(parts[1].contains("Memory: 50 MB now, 500 MB peak"))
    }

    @Test func reportRoundsHalfwayValues() {
        var log = PerfLog()
        log.recordSample(cpu: 0.05, memoryMB: 10.5, at: t0)
        log.recordHookLatency(ms: 2.5, at: t0)
        let report = log.report(now: t0, version: "1", system: "s")
        #expect(report.contains("Memory: 11 MB now, 11 MB peak"))
        #expect(report.contains("Hooks: 1 events, 3 ms median, 3 ms p95, 3 ms max"))
    }

    @Test func summaryTypesAreValueTypes() {
        var s = PerfLog.Summary()
        s.cpuPeak = 1
        s.scene.frames = 2
        s.hooks.events = 3
        #expect(s != PerfLog.Summary())
        #expect(PerfLog.Summary() == PerfLog.Summary())
    }
}
