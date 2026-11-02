import Foundation

/// Runs commands on a machine through its transport: the user's own command, e.g. `ssh devbox`. Ambient has no
/// client, listener, crypto or credentials of its own. The remote command is one last argument, a shell string.
public struct RemoteTransport: Sendable {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: Data
        public let stderr: String
        public let timedOut: Bool

        public var ok: Bool { status == 0 && !timedOut }
        public var text: String { String(decoding: stdout, as: UTF8.self) }
        /// Stdout's last line: a login shell can print anything before the command's own output.
        public var lastLine: Data { Data(stdout.split(separator: UInt8(ascii: "\n")).last ?? []) }
        /// The first word of that line, as plain text. It came from the machine, so it's safe to print only like this.
        public var lastLineWord: String {
            RemoteEventDecoder.plainText(String(decoding: lastLine, as: UTF8.self), max: 128)?
                .split(separator: " ").first.map(String.init) ?? ""
        }
    }

    public let argv: [String]

    public init(argv: [String]) {
        self.argv = argv
    }

    /// `ambient-remote <arguments>` as a command for the machine's login shell. Stays quoted the same in sh, bash,
    /// zsh and fish. `arguments` are built by Ambient and never contain remote text.
    public static func shim(_ arguments: String) -> String {
        #"sh -c '"$HOME/.ambient/bin/ambient-remote" \#(arguments)'"#
    }

    /// Runs the shim sent on stdin and asks who the machine is. Nothing is read from there or left behind.
    public static let identify = "sh -s identity"

    /// `follow` replaces that `sh`, so ending the transport ends it.
    public static func follow(since seq: Int64) -> String {
        #"sh -c 'exec "$HOME/.ambient/bin/ambient-remote" follow --since \#(seq)'"#
    }

    /// Writes stdin to the shim's path atomically, private to the user.
    public static let copyShim = #"sh -c 'umask 077 && mkdir -p "$HOME/.ambient/bin" && cat > "$HOME/.ambient/bin/ambient-remote.new" && chmod 700 "$HOME/.ambient/bin/ambient-remote.new" && mv -f "$HOME/.ambient/bin/ambient-remote.new" "$HOME/.ambient/bin/ambient-remote"'"#

    /// Prints the installed shim's SHA-256, by a tool that isn't the shim.
    public static let hashShim = #"sh -c 'f="$HOME/.ambient/bin/ambient-remote"; if command -v sha256sum > /dev/null 2>&1; then sha256sum "$f"; else shasum -a 256 "$f"; fi'"#

    /// The transport as a `Process`, ready to run. Apps opened from the Finder get a short PATH, so the usual
    /// places for ssh wrappers are added. Stdin is closed: the hub sends nothing but the command line.
    public func process(for remote: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv + [remote]
        var environment = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin"]
        let path = environment["PATH"].map { $0.split(separator: ":").map(String.init) } ?? ["/usr/bin", "/bin"]
        environment["PATH"] = (path + extra.filter { !path.contains($0) }).joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        return process
    }

    /// Runs one command to the end. `input` is what the machine reads on stdin.
    public func run(_ remote: String, input: Data? = nil, timeout: TimeInterval = 30) -> Result {
        let process = process(for: remote)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let stdin = input.map { _ in Pipe() }
        if let stdin { process.standardInput = stdin }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return Result(status: 127, stdout: Data(), stderr: String(describing: error), timedOut: false)
        }
        let collected = Collected()
        let readers = DispatchGroup()
        for (pipe, isError) in [(out, false), (err, true)] {
            readers.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collected.set(data, isError: isError)
                readers.leave()
            }
        }
        if let stdin, let input {
            // A transport that exits first, as a failed sign-in does, mustn't take this process with it.
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
        }
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
        }
        _ = readers.wait(timeout: .now() + 2)
        let (stdout, stderr) = collected.get()
        return Result(status: timedOut ? -1 : process.terminationStatus, stdout: stdout,
                      stderr: String(decoding: stderr, as: UTF8.self), timedOut: timedOut)
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()

        func set(_ data: Data, isError: Bool) {
            lock.lock(); defer { lock.unlock() }
            if isError { stderr = data } else { stdout = data }
        }

        func get() -> (Data, Data) {
            lock.lock(); defer { lock.unlock() }
            return (stdout, stderr)
        }
    }
}

/// Splits a byte stream into lines. A line past the cap isn't buffered: the rest of it is skipped, and it comes out
/// as a line just over the cap, so the decoder rejects and counts it like any other.
struct RemoteLineSplitter {
    private let cap: Int
    private var buffer = Data()
    private var skipping = false

    init(cap: Int = RemoteEventDecoder.maxLineBytes) {
        self.cap = cap
    }

    mutating func feed(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var rest = chunk[...]
        while let newline = rest.firstIndex(of: UInt8(ascii: "\n")) {
            let piece = rest[rest.startIndex..<newline]
            rest = rest[(newline + 1)...]
            if skipping {
                skipping = false
                lines.append(Data(count: cap + 1))
            } else if buffer.count + piece.count > cap {
                buffer.removeAll()
                lines.append(Data(count: cap + 1))
            } else {
                buffer.append(piece)
                if !buffer.isEmpty { lines.append(buffer) }
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !skipping {
            if buffer.count + rest.count > cap {
                buffer.removeAll()
                skipping = true
            } else {
                buffer.append(rest)
            }
        }
        return lines
    }
}
