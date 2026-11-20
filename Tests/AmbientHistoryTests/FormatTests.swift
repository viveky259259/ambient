import Foundation
import Testing
@testable import AmbientHistory

/// The two files history stores are read by other people's copies of Ambient, long after they were written.
@Suite struct FormatTests {
    @Test func chatRecord() throws { try Fixture.roundTrip("ChatRecord.v1.json", Sample.record) }

    @Test func cardFile() throws {
        var file = Sample.cardFile(url: "https://example.com/page.html")
        file.cards[0].why = "Finished tasks never left the board."
        file.cards[0].rejected = "Capping the board at a fixed size."
        file.cards[0].verified = "12 tests pass."
        file.cards[0].source = "claude-haiku-5-5"
        try Fixture.roundTrip("CardFile.v1.json", file)
    }

    @Test func everyTouchKindSaysWhetherItChanges() {
        #expect(FileTouch.How.allCases.filter(\.changes) == [.edit, .write, .shell])
    }

    @Test func encodingIsStable() throws {
        #expect(try HistoryCoding.encode(Sample.record) == HistoryCoding.encode(Sample.record))
        let text = String(decoding: try HistoryCoding.encode(Sample.session), as: UTF8.self)
        #expect(text.contains("\"startedAt\":\"2026-11-18T"))
        #expect(!text.contains("\\/"))
    }
}

@Suite struct RedactorTests {
    private let redactor = Redactor(home: "/Users/pat")

    @Test func everyPatternCompiles() {
        for pattern in SecretPatternsProbe.all {
            #expect((try? NSRegularExpression(pattern: pattern)) != nil, "\(pattern) isn't a valid pattern")
        }
    }

    @Test(arguments: [
        ("token ghp_" + String(repeating: "a", count: 36) + " end", "token [redacted: GitHub token] end"),
        ("AKIAIOSFODNN7EXAMPLE", "[redacted: AWS access key]"),
        ("key sk-ant-" + String(repeating: "x", count: 30), "key [redacted: Anthropic API key]"),
        ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345", "Authorization: Bearer [redacted: bearer token]"),
        ("export STRIPE_SECRET_KEY=sk_live_0123456789abcdef", "export STRIPE_SECRET_KEY=[redacted: credential]"),
        ("DB_PASSWORD='correct horse battery'", "DB_PASSWORD='correct horse battery'"),
        ("DB_PASSWORD='correct-horse-battery'", "DB_PASSWORD=[redacted: credential]"),
        ("https://deploy:hunter2secret@example.com/repo.git", "https://deploy:[redacted: password in a URL]@example.com/repo.git"),
        ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop", "[redacted: JSON web token]"),
    ])
    func blanksSecrets(_ text: String, _ expected: String) {
        #expect(redactor.clean(text) == expected)
    }

    @Test func blanksAWholePrivateKey() {
        let text = "before\n-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\nAAAA\n-----END OPENSSH PRIVATE KEY-----\nafter"
        #expect(redactor.clean(text) == "before\n[redacted: private key]\nafter")
        #expect(redactor.clean("-----BEGIN RSA PRIVATE KEY-----\nabc") == "[redacted: private key]")
    }

    @Test func leavesOrdinaryCodeAlone() {
        let code = "let token: String = makeToken()\nfunc apiKey() -> String { key }\nsk-ant-test\nTOKEN=short"
        #expect(redactor.clean(code) == code)
    }

    @Test func writesTheHomeFolderAsATilde() {
        // Another user's folder that only starts the same way is not this one.
        #expect(redactor.clean("cd /Users/pat/code && ls /Users/patricia /Users/pat") == "cd ~/code && ls /Users/patricia ~")
        #expect(redactor.clean("open /Users/pat/code/a.swift") == "open ~/code/a.swift")
        #expect(Redactor(home: nil).clean("/Users/pat/x") == "/Users/pat/x")
        #expect(Redactor(home: "/").clean("/Users/pat/x") == "/Users/pat/x")
    }

    @Test func staysFastOnLongOutput() {
        let long = String(repeating: "INFO request 4f2a took 12ms path=/api/v1/items?id=42 status=200\n", count: 4_000)
        let started = Date()
        _ = redactor.clean(long)
        #expect(Date().timeIntervalSince(started) < 2)
    }
}

/// Every pattern the redactor uses, for the test that they compile: one that doesn't is skipped without a word.
enum SecretPatternsProbe {
    static var all: [String] {
        (Redactor.extra + Redactor.named).map(\.regex)
    }
}
