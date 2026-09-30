import Foundation
import Testing
@testable import AmbientCore

private let start = Date(timeIntervalSince1970: 1_790_700_000)

@Suite struct PerfLogTests {
    @Test func cpuAndMemoryAverageAndPeakOverTheWindow() {
        var log = PerfLog()
        log.recordSample(cpu: 2, memoryMB: 40, at: start)
        log.recordSample(cpu: 6, memoryMB: 44, at: start.addingTimeInterval(30))
        log.recordSample(cpu: 1, memoryMB: 42, at: start.addingTimeInterval(90))
        let s = log.summary(over: 3_600, now: start.addingTimeInterval(100))
        #expect(s.cpuAverage == 3)
        #expect(s.cpuPeak == 6)
        #expect(s.memoryNowMB == 42)
        #expect(s.memoryPeakMB == 44)
    }

    @Test func framesGiveARateAndALateShareFromTheirIntervals() {
        var log = PerfLog()
        // Nine frames on time at 12 fps, one that came a whole budget late.
        for i in 0..<9 { log.recordFrame(intervalMs: 1000.0 / 12, budgetMs: 1000.0 / 12, source: .scene, at: start.addingTimeInterval(Double(i))) }
        log.recordFrame(intervalMs: 2000.0 / 12, budgetMs: 1000.0 / 12, source: .scene, at: start.addingTimeInterval(9))
        log.recordFrame(intervalMs: 1000.0 / 60, budgetMs: 1000.0 / 60, source: .effect, at: start.addingTimeInterval(10))
        let s = log.summary(over: 3_600, now: start.addingTimeInterval(20))
        #expect(s.scene.frames == 10)
        #expect(abs(s.scene.fps - 10 / (11.0 / 12)) < 1e-9)
        #expect(s.scene.lateShare == 0.1)
        #expect(s.effect.frames == 1)
        #expect(abs(s.effect.fps - 60) < 1e-9)
        #expect(s.effect.lateShare == 0)
    }

    @Test func aPauseIsNotAFrame() {
        var log = PerfLog()
        log.recordFrame(intervalMs: 5_000, budgetMs: 1000.0 / 12, source: .scene, at: start)
        #expect(log.summary(over: 3_600, now: start).scene.frames == 0)
    }

    @Test func hookLatencyPercentiles() {
        var log = PerfLog()
        for ms in 1...100 { log.recordHookLatency(ms: Double(ms), at: start) }
        let s = log.summary(over: 3_600, now: start)
        #expect(s.hooks.events == 100)
        #expect(s.hooks.medianMs == 50)
        #expect(s.hooks.p95Ms == 95)
        #expect(s.hooks.maxMs == 100)
    }

    @Test func theWindowLeavesOlderMinutesOut() {
        var log = PerfLog()
        log.recordSample(cpu: 50, memoryMB: 80, at: start)
        log.recordFrame(intervalMs: 80, budgetMs: 80, source: .scene, at: start)
        log.recordSample(cpu: 1, memoryMB: 40, at: start.addingTimeInterval(2 * 3_600))
        let s = log.summary(over: 3_600, now: start.addingTimeInterval(2 * 3_600))
        #expect(s.cpuPeak == 1)
        #expect(s.memoryPeakMB == 40)
        #expect(s.scene.frames == 0)
        #expect(log.summary(over: 86_400, now: start.addingTimeInterval(2 * 3_600)).cpuPeak == 50)
    }

    @Test func keepsADayAtMost() {
        var log = PerfLog()
        log.recordSample(cpu: 90, memoryMB: 99, at: start)
        for m in 1...1_500 { log.recordSample(cpu: 1, memoryMB: 30, at: start.addingTimeInterval(Double(m) * 60)) }
        #expect(log.minuteCount <= PerfLog.maxMinutes)
        #expect(log.summary(over: 10 * 86_400, now: start.addingTimeInterval(1_500 * 60)).cpuPeak == 1)
    }

    @Test func anEmptyLogSummarisesToZeros() {
        let s = PerfLog().summary(over: 3_600, now: start)
        #expect(s.cpuAverage == 0 && s.cpuPeak == 0 && s.memoryNowMB == 0)
        #expect(s.scene.frames == 0 && s.scene.fps == 0 && s.scene.lateShare == 0)
        #expect(s.hooks.events == 0 && s.hooks.medianMs == 0)
    }

    @Test func theReportStatesEveryFigure() {
        var log = PerfLog()
        log.recordSample(cpu: 2.5, memoryMB: 41.2, at: start)
        log.recordFrame(intervalMs: 100, budgetMs: 1000.0 / 12, source: .scene, at: start)
        log.recordHookLatency(ms: 12, at: start)
        let report = log.report(now: start.addingTimeInterval(10), version: "0.4.0", system: "macOS 27.0 (arm64)")
        #expect(report.contains("Ambient 0.4.0"))
        #expect(report.contains("macOS 27.0 (arm64)"))
        #expect(report.contains("Last hour"))
        #expect(report.contains("Last 24 hours"))
        #expect(report.contains("CPU: 2.5% average, 2.5% peak"))
        #expect(report.contains("Memory: 41 MB now, 41 MB peak"))
        #expect(report.contains("Wallpaper: 1 frames, 10.0 fps, 0% late"))
        #expect(report.contains("Hooks: 1 events, 12 ms median, 12 ms p95"))
    }
}
