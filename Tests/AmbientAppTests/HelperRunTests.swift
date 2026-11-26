import Foundation
import Testing
@testable import AmbientApp

private func openDescriptors() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0 }

@Suite(.serialized) struct HelperRunTests {
    /// The speaker and microphone start their helpers again and again, so a run has to leave no pipe open behind it,
    /// whether the helper ends by itself or is stopped.
    @Test func aHelperRunLeavesNoPipesOpen() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: script) }
        try "#!/bin/sh\necho '{\"event\":\"playing\"}'\necho chatter >&2\n[ \"$1\" = wait ] && cat >/dev/null\nexit 0\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        func runToTheEnd(_ argument: String, stop: Bool) {
            let ended = DispatchSemaphore(value: 0)
            let run = HelperRun(script, [argument])
            #expect(run.start(onEvent: { _ in }, onExit: { ended.signal() }))
            if stop { run.stop() }
            #expect(ended.wait(timeout: .now() + 10) == .success)
        }

        runToTheEnd("exit", stop: false)
        let before = openDescriptors()
        for _ in 0..<30 { runToTheEnd("exit", stop: false) }
        for _ in 0..<30 { runToTheEnd("wait", stop: true) }
        let after = openDescriptors()
        #expect(after - before < 40, "\(before) descriptors open before 60 runs, \(after) after")
    }
}
