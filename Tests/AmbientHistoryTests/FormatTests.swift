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
        ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345", "Authorization: Bearer [redacted: authorization header]"),
        ("fetch(url, { headers: { \"X-Auth\": \"Bearer abcdefghijklmnopqrstuvwxyz\" } })", "fetch(url, { headers: { \"X-Auth\": \"Bearer [redacted: bearer token]\" } })"),
        ("[default]\n  aws_secret_access_key=wJalrXUtnFEMI\npassword = hunter2", "[default]\n  aws_secret_access_key=[redacted: credential]\npassword = [redacted: credential]"),
        ("export STRIPE_SECRET_KEY=sk_live_0123456789abcdef", "export STRIPE_SECRET_KEY=[redacted: credential]"),
        ("DB_PASSWORD=hunter2", "DB_PASSWORD=[redacted: credential]"),
        ("DB_PASSWORD=\"correct horse battery staple\" next", "DB_PASSWORD=[redacted: credential] next"),
        ("STRIPE_KEY=sk_live_0123", "STRIPE_KEY=[redacted: credential]"),
        ("aws_secret_access_key = wJalrXUtnFEMI/K7MDENG", "aws_secret_access_key = [redacted: credential]"),
        ("{\"env\":{\"API_KEY\":\"abcdef123\"}}", "{\"env\":{\"API_KEY\":[redacted: credential]}}"),
        ("  \"password\": \"s3cretpw\",", "  \"password\": [redacted: credential],"),
        ("Authorization: Basic dXNlcjpwYXNzd29yZA==", "Authorization: Basic [redacted: authorization header]"),
        ("curl -u admin:hunter2 https://example.com", "curl -u [redacted: user name and password] https://example.com"),
        ("postgres://app:pw123@db.internal/x", "postgres://app:[redacted: password in a URL]@db.internal/x"),
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
        let pgp = "x\n-----BEGIN PGP PRIVATE KEY BLOCK-----\n\nlQOYBF\n-----END PGP PRIVATE KEY BLOCK-----\ny"
        #expect(redactor.clean(pgp) == "x\n[redacted: private key]\ny")
    }

    @Test func leavesOrdinaryCodeAlone() {
        let code = "let token: String = makeToken()\nfunc apiKey() -> String { key }\nsk-ant-test\nTOKEN=abc\n"
            + "MAX_TOKENS=4000\nUSE_TOKEN=true\nlet password = field.text\ncase apiKey = \"api_key\"\ngit@github.com:acme/widgets.git\n"
            + "https://example.com:8443/path@v2\nfunc f(token: String, user: User) {}"
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
