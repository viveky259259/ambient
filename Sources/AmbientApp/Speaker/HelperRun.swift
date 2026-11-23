import Foundation

/// One run of `Contents/Helpers/ambient-speaker` with `--app`: the JSON lines it writes are its events, and it stops
/// once its standard input closes, so it never outlives the app.
final class HelperRun {
    private let process = Process()
    private let input = Pipe()

    init(_ helper: URL, _ arguments: [String]) {
        process.executableURL = helper
        process.arguments = arguments
    }

    /// Starts it, handing each event and then its end to the main queue. False if it couldn't start.
    func start(onEvent: @escaping ([String: Any]) -> Void, onExit: @escaping () -> Void) -> Bool {
        let output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return false }
        let process = process, input = input
        // Everything it says is heard before it's known to have stopped: it has stopped once its output ends.
        Thread {
            let reader = output.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = autoreleasepool { reader.availableData }
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard line.first == UInt8(ascii: "{"),
                          let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    DispatchQueue.main.async { onEvent(event) }
                }
            }
            // Closed now, not whenever the handle happens to be freed: the speaker and microphone start helpers again
            // and again for as long as the app runs.
            try? reader.close()
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
            DispatchQueue.main.async(execute: onExit)
        }.start()
        // Standard error isn't read for anything but has to be drained, or a chatty helper would block on it.
        Thread {
            let reader = errors.fileHandleForReading
            autoreleasepool { _ = reader.readDataToEndOfFile() }
            try? reader.close()
        }.start()
        return true
    }

    /// Its input closing stops it cleanly; it's terminated if it hasn't stopped 3 seconds later.
    func stop() {
        try? input.fileHandleForWriting.close()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
    }
}
