import Foundation
import Testing

/// Golden files for the formats Ambient stores or sends (`docs/superpowers/specs/2026-11-13-modular-packages-design.md`,
/// rule 4). Each test encodes a known value, checks it against the fixture, and decodes the fixture back.
///
/// A released fixture is never edited: a format change adds a new one (`.v2`) and the old one must still decode. To
/// add a fixture, run the tests with `AMBIENT_RECORD_FIXTURES=1`. That writes only fixtures that are missing, from what
/// the code produces today; it never overwrites one.
///
/// Each test target keeps its own copy of this file (AmbientContractsTests, AmbientCoreTests): there is no shared
/// testing library.
enum Fixture {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static var recording: Bool { ProcessInfo.processInfo.environment["AMBIENT_RECORD_FIXTURES"] == "1" }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// The fixture `name`, after checking it holds the same JSON as `written`: what the code writes today.
    @discardableResult
    static func check(_ name: String, matches written: Data,
                      sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let url = url(name)
        if recording, !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try canonical(written, pretty: true).write(to: url)
        }
        let fixture = try Data(contentsOf: url)
        #expect(try canonical(fixture) == canonical(written), "\(name) no longer matches what the code writes",
                sourceLocation: sourceLocation)
        return fixture
    }

    /// The same for a file of JSON lines, one per value.
    @discardableResult
    static func checkLines(_ name: String, match written: [Data],
                           sourceLocation: SourceLocation = #_sourceLocation) throws -> [Data] {
        let url = url(name)
        if recording, !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var file = Data()
            for line in written { file += try canonical(line) + Data("\n".utf8) }
            try file.write(to: url)
        }
        let fixture = try lines(name)
        #expect(fixture.count == written.count, "\(name) has \(fixture.count) lines, the code wrote \(written.count)",
                sourceLocation: sourceLocation)
        for (index, (saved, now)) in zip(fixture, written).enumerated() {
            #expect(try canonical(saved) == canonical(now), "\(name) line \(index + 1) no longer matches",
                    sourceLocation: sourceLocation)
        }
        return fixture
    }

    /// The non-empty lines of a fixture.
    static func lines(_ name: String) throws -> [Data] {
        try Data(contentsOf: url(name)).split(separator: UInt8(ascii: "\n")).map { Data($0) }
    }

    /// Encodes and decodes the way Ambient's files and socket do: a plain `JSONEncoder`, dates as reference-date seconds.
    static func roundTrip<T: Codable & Equatable>(_ name: String, _ value: T,
                                                  sourceLocation: SourceLocation = #_sourceLocation) throws {
        let fixture = try check(name, matches: JSONEncoder().encode(value), sourceLocation: sourceLocation)
        #expect(try JSONDecoder().decode(T.self, from: fixture) == value, "\(name) decodes to something else",
                sourceLocation: sourceLocation)
    }

    /// JSON with sorted keys, so two encodings compare by value rather than by key order.
    static func canonical(_ data: Data, pretty: Bool = false) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }
}
