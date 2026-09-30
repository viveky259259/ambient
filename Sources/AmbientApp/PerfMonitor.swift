import AmbientCore
import AppKit
import Darwin
import QuartzCore

/// Measures what Ambient costs this Mac and keeps it in memory: CPU and memory every five seconds, how long each
/// wallpaper and notch-effect frame takes to draw, and how long hook events take to arrive. Nothing leaves the Mac;
/// Settings › Performance shows it, and its report can be copied or saved by hand.
final class PerfMonitor: ObservableObject {
    static let shared = PerfMonitor()

    /// Bumped with each sample, so an open Settings pane refreshes.
    @Published private(set) var revision = 0
    private(set) var log = PerfLog()
    private var timer: Timer?
    private var lastCPU: (wall: CFTimeInterval, cpu: Double)?

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.sample() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One drawn frame. Called on the main thread from the scene's canvases; constant time.
    func frame(ms: Double, source: PerfLog.FrameSource) {
        log.recordFrame(ms: ms, source: source, at: Date())
    }

    /// A hook event arrived; `sent` is when the hook stamped it.
    func hookEvent(sent: Date) {
        let ms = Date().timeIntervalSince(sent) * 1000
        guard ms >= 0, ms < 60_000 else { return }   // a clock change or a replayed event, not latency
        log.recordHookLatency(ms: ms, at: Date())
    }

    func summary(over window: TimeInterval) -> PerfLog.Summary { log.summary(over: window, now: Date()) }

    func report() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "arm64"
        #if arch(x86_64)
        arch = "x86_64"
        #endif
        return log.report(now: Date(), version: AmbientVersion.current,
                          system: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(arch))")
    }

    // MARK: - Sampling

    private func sample() {
        let now = CACurrentMediaTime(), cpu = Self.cpuSeconds()
        defer { lastCPU = (now, cpu) }
        guard let last = lastCPU, now > last.wall else { return }
        // Share of one core over the interval, as Activity Monitor shows it.
        let percent = max(0, (cpu - last.cpu) / (now - last.wall) * 100)
        log.recordSample(cpu: percent, memoryMB: Self.footprintMB(), at: Date())
        revision &+= 1
    }

    /// User and system CPU time this process has used so far.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// The memory footprint Activity Monitor shows as "Memory".
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
