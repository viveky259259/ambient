import Foundation
import Testing
@testable import AmbientCore

/// The app runs for days, starting transports over and over, so every pipe it opens has to be closed when the child
/// is done, not left for an autorelease pool that a long-lived thread never drains. The counts are this whole
/// process's, so the limits leave room for other tests running at the same time; a leak is two descriptors a run.
private func openDescriptors() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0 }

@Suite(.serialized) struct PipeLeakTests {
    @Test func aTransportRunClosesItsPipes() {
        let transport = RemoteTransport(argv: ["/bin/sh", "-c"])
        _ = transport.run("true")
        let before = openDescriptors()
        for _ in 0..<60 { _ = transport.run("echo out; echo err >&2") }
        for _ in 0..<30 { _ = transport.run("cat >/dev/null", input: Data("x".utf8)) }
        let after = openDescriptors()
        #expect(after - before < 60, "\(before) descriptors open before 90 runs, \(after) after")
    }

    @Test func aLinkThatKeepsFailingClosesEachConnectionsPipes() {
        let machine = Machine(id: "asleep", transport: ["/bin/sh", "-c", "echo 'ssh: connect to host asleep: Operation timed out' >&2; exit 255"],
                              fingerprint: "id:" + String(repeating: "a", count: 32))
        var options = RemoteLink.Options()
        options.backoff.base = 0.01
        options.backoff.limit = 0.02
        let link = RemoteLink(machine: machine, cursor: RemoteCursor(seq: 0, epoch: String(repeating: "0", count: 16)), options: options,
                              deliver: { _, _, applied in applied() }, report: { _, _ in })
        let before = openDescriptors()
        link.start()
        Thread.sleep(forTimeInterval: 3)
        // Measured while it's still running: its thread's pool drains when it stops, which hid the leak.
        let during = openDescriptors()
        link.stop()
        #expect(during - before < 40, "\(before) descriptors open before, \(during) after 3 s of failing connections")
    }
}
