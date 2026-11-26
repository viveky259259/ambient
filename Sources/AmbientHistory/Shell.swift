import Foundation

/// Runs the command-line tools history leans on (`git`, `aws`, `gh`), so tests can stand in for them.
public struct Shell: Sendable {
    public struct Output: Equatable, Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String

        public init(status: Int32, stdout: String = "", stderr: String = "") {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }

        public var succeeded: Bool { status == 0 }
    }

    /// The tool's name ("git"), its arguments, the folder to run in, and what to write to its standard input.
    public var run: @Sendable (_ tool: String, _ arguments: [String], _ folder: String?, _ input: Data?) -> Output

    public init(run: @escaping @Sendable (String, [String], String?, Data?) -> Output) {
        self.run = run
    }

    public func callAsFunction(_ tool: String, _ arguments: [String], in folder: String? = nil,
                               input: Data? = nil) -> Output {
        run(tool, arguments, folder, input)
    }

    /// The longest any one command may run. A tool that hangs (a network that never answers, a prompt nobody sees)
    /// is stopped, so one stuck capture can't hold up every later one.
    static let timeLimit: TimeInterval = 600

    /// Where to look for tools when `PATH` is the short one a GUI app or a hook gets.
    static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    /// The real thing. A tool that isn't installed reports status 127, as a shell would.
    public static let system = Shell { tool, arguments, folder, input in
        guard let executable = find(tool) else {
            return Output(status: 127, stderr: "\(tool): command not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let folder { process.currentDirectoryURL = URL(fileURLWithPath: folder, isDirectory: true) }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ((environment["PATH"].map { [$0] } ?? []) + extraPaths).joined(separator: ":")
        // Never stop to ask: nobody is watching a capture that the app started.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["AWS_PAGER"] = ""
        process.environment = environment
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do { try process.run() } catch {
            return Output(status: 126, stderr: "\(tool): \(error.localizedDescription)")
        }
        let running = Running(process)
        let watchdog = DispatchWorkItem { running.stop() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeLimit, execute: watchdog)
        defer { watchdog.cancel() }
        // Both pipes are drained while the tool runs: one left to fill would block it for good.
        let errData = Collected()
        let errReader = Thread { errData.set(err.fileHandleForReading.readDataToEndOfFile()) }
        errReader.start()
        if let input {
            // A tool that exits without reading its input must cost a failed write, not the whole process.
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stderr = errData.wait()
        return Output(status: process.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: stderr, as: UTF8.self))
    }

    static func find(_ tool: String) -> String? {
        if tool.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for folder in path.split(separator: ":").map(String.init) + extraPaths {
            let candidate = (folder as NSString).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// A started process, for the watchdog that stops it when it runs too long.
private final class Running: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) { self.process = process }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}

/// One value handed from a reader thread to the thread waiting for it.
private final class Collected: @unchecked Sendable {
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    func set(_ value: Data) {
        data = value
        done.signal()
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}
