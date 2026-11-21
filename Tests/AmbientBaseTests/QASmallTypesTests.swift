import Darwin
import Foundation
import Testing
@testable import AmbientBase

// MARK: - Loopback

@Suite("URL.isLoopback")
struct QALoopbackTests {
    @Test(arguments: [
        "http://127.0.0.1", "http://127.0.0.1:8080/v1/chat", "https://127.0.0.1/",
        "http://localhost", "http://localhost:11434/api", "https://localhost/x?y=1#z",
        "http://[::1]", "http://[::1]:8080/path",
        "HTTP://LOCALHOST", "Https://LocalHost:1/", "http://user:pass@localhost/",
    ])
    func loopbackHTTPURLs(_ s: String) throws {
        let url = try #require(URL(string: s))
        #expect(url.isLoopback, "\(s)")
    }

    @Test(arguments: [
        // Other hosts
        "http://example.com", "https://api.anthropic.com/v1", "http://127.0.0.2", "http://127.1",
        "http://0.0.0.0", "http://192.168.1.10", "http://10.0.0.1", "http://[::2]", "http://[::ffff:127.0.0.1]",
        "http://[0:0:0:0:0:0:0:1]",
        // Look-alikes
        "http://localhost.example.com", "http://127.0.0.1.nip.io", "http://notlocalhost", "http://localhost.",
        "http://evil.com/localhost", "http://evil.com?h=127.0.0.1", "http://localhost@evil.com",
        // Other schemes
        "ws://localhost", "wss://127.0.0.1", "ftp://localhost", "file:///tmp/x", "file://localhost/tmp/x",
        "unix:///tmp/ambient.sock", "mailto:me@localhost",
        // Malformed / hostless
        "localhost", "localhost:8080", "127.0.0.1:80/x", "/just/a/path", "http:///path", "http://", "http:localhost",
    ])
    func notLoopback(_ s: String) {
        guard let url = URL(string: s) else { return }  // Unparseable is "not loopback" by construction.
        #expect(!url.isLoopback, "\(s)")
    }

    @Test func fileURLIsNeverLoopback() {
        #expect(!URL(fileURLWithPath: "/tmp/localhost").isLoopback)
    }
}

// MARK: - RGB

@Suite("RGB")
struct QARGBTests {
    @Test func memberwiseInit() {
        let c = RGB(r: 0.1, g: 0.2, b: 0.3)
        #expect(c.r == 0.1 && c.g == 0.2 && c.b == 0.3)
    }

    static let sixDigit: [(String, Double, Double, Double)] = [
        ("#FF0000", 255, 0, 0), ("00ff00", 0, 255, 0), ("#0000FF", 0, 0, 255),
        ("#ffffff", 255, 255, 255), ("#000000", 0, 0, 0), ("#AbCdEf", 171, 205, 239), ("#808080", 128, 128, 128),
    ]

    @Test(arguments: sixDigit)
    func sixDigitHex(hex: String, r: Double, g: Double, b: Double) {
        #expect(RGB(hex: hex) == RGB(r: r / 255, g: g / 255, b: b / 255))
    }

    /// Invalid input is black rather than a crash.
    @Test(arguments: ["", "#", "#GGGGGG", "zzz", " #FFFFFF", "#FFFFFF ", "0xFFFFFF", "##FFFFFF", "-1", "#123456789"])
    func invalidHexIsBlack(_ hex: String) {
        #expect(RGB(hex: hex) == RGB(r: 0, g: 0, b: 0))
    }

    @Test func threeDigitShorthandIsReadAsAPlainNumber() {
        // Current behaviour: "#FFF" is 0x000FFF, not CSS shorthand for white.
        #expect(RGB(hex: "#FFF") == RGB(r: 0, g: 15.0 / 255, b: 1))
    }

    @Test func eightDigitHexKeepsTheLowSixDigits() {
        // Current behaviour: the leading byte is dropped, so "#RRGGBBAA" reads as GG BB AA.
        #expect(RGB(hex: "#11223344") == RGB(r: 0x22 / 255.0, g: 0x33 / 255.0, b: 0x44 / 255.0))
    }

    @Test func componentsStayInUnitRange() {
        for hex in ["#000000", "#FFFFFF", "#7F7F7F", "#123456", "#FEDCBA"] {
            let c = RGB(hex: hex)
            #expect((0...1).contains(c.r) && (0...1).contains(c.g) && (0...1).contains(c.b))
        }
    }

    private static let black = RGB(r: 0, g: 0, b: 0)
    private static let white = RGB(r: 1, g: 1, b: 1)

    @Test func mixEndpointsAndMidpoint() {
        #expect(Self.black.mixed(with: Self.white, 0) == Self.black)
        #expect(Self.black.mixed(with: Self.white, 1) == Self.white)
        #expect(Self.black.mixed(with: Self.white, 0.5) == RGB(r: 0.5, g: 0.5, b: 0.5))
        let a = RGB(r: 0.2, g: 0.4, b: 1), b = RGB(r: 0.6, g: 0, b: 0)
        let m = a.mixed(with: b, 0.25)
        #expect(abs(m.r - 0.3) < 1e-12 && abs(m.g - 0.3) < 1e-12 && abs(m.b - 0.75) < 1e-12)
    }

    @Test(arguments: [-1.0, -0.0001, -Double.infinity])
    func mixClampsBelowZero(t: Double) {
        #expect(Self.black.mixed(with: Self.white, t) == Self.black)
    }

    @Test(arguments: [1.0001, 2.0, Double.infinity])
    func mixClampsAboveOne(t: Double) {
        #expect(Self.black.mixed(with: Self.white, t) == Self.white)
    }

    @Test func mixWithNaNStaysFinite() {
        let m = Self.black.mixed(with: Self.white, .nan)
        #expect(m.r.isFinite && m.g.isFinite && m.b.isFinite)
    }

    @Test func mixWithItselfIsIdentity() {
        let c = RGB(hex: "#336699")
        #expect(c.mixed(with: c, 0.7) == c)
    }
}

// MARK: - Version

@Suite("AmbientVersion")
struct QAVersionTests {
    @Test func isSemanticVersion() throws {
        let parts = AmbientVersion.current.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3)
        for part in parts {
            #expect(!part.isEmpty && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber), "\(part)")
            #expect(part == "0" || !part.hasPrefix("0"), "no leading zeros: \(part)")
        }
    }

    /// scripts/build-app.sh extracts the version with `sed -n 's/.*current = "\(.*\)".*/\1/p'`; that needs exactly one
    /// such line in Version.swift, and it must agree with the compiled constant.
    @Test func buildScriptCanExtractTheVersion() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AmbientBase/Version.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let lines = text.split(separator: "\n").filter { $0.contains("current = \"") }
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        let start = try #require(line.range(of: "current = \"")).upperBound
        let rest = line[start...]
        let end = try #require(rest.lastIndex(of: "\""))
        #expect(String(rest[..<end]) == AmbientVersion.current)
    }
}

// MARK: - TextLimits

@Suite("TextLimits")
struct QATextLimitsTests {
    @Test func values() {
        #expect(TextLimits.detail == 80)
        #expect(TextLimits.message == 160)
        #expect(TextLimits.sessionId == 128)
        #expect(TextLimits.agentName == 24)
    }

    @Test func limitsArePositiveAndOrdered() {
        #expect(TextLimits.agentName > 1)
        #expect(TextLimits.agentName < TextLimits.detail)
        #expect(TextLimits.detail < TextLimits.message)
    }

    @Test(arguments: [TextLimits.detail, TextLimits.message, TextLimits.sessionId, TextLimits.agentName])
    func trimHonoursEachLimit(limit: Int) {
        let long = String(repeating: "word ", count: 200)
        let out = Trim.truncate(long, max: limit)
        #expect(out.count == limit)
        #expect(out.hasSuffix("…"))
    }
}

// MARK: - ProcessProbe

@Suite("ProcessProbe")
struct QAProcessProbeTests {
    @Test func currentProcessIsAlive() {
        #expect(ProcessProbe.isAlive(getpid()))
    }

    @Test func parentProcessIsAlive() {
        #expect(ProcessProbe.isAlive(getppid()))
    }

    /// launchd is every process's ancestor; it is owned by root, so `kill(1, 0)` fails with EPERM — still alive.
    @Test func launchdCountsAsAliveThroughEPERM() {
        #expect(ProcessProbe.isAlive(1))
    }

    @Test(arguments: [Int32(0), -1, -12345, Int32.min])
    func unknownPidsCountAsAlive(pid: Int32) {
        #expect(ProcessProbe.isAlive(pid))
    }

    /// macOS pids never exceed 99,999, so this pid cannot exist.
    @Test func impossiblePidIsDead() {
        #expect(!ProcessProbe.isAlive(Int32.max))
    }

    @Test func aReapedChildIsDead() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        // The child has been reaped; its pid is free. Reuse within this instant is vanishingly unlikely.
        #expect(!ProcessProbe.isAlive(child.processIdentifier))
    }
}
