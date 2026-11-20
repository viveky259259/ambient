import Foundation
import Testing
@testable import AmbientHistory

private let written = #"{"summary":"Tasks expire after three days.","why":"Nothing ever left the board.","rejected":"A fixed cap.","verified":"12 tests pass.","evidence":[4,8,99,4]}"#

@Suite struct CardWriterTests {
    @Test func withoutAModelCardsComeFromTheChat() {
        let result = CardWriter(model: nil).cards(for: Sample.record)
        #expect(result.cards.map(\.source) == ["extract", "extract"])
        #expect(result.failures.isEmpty)
    }

    @Test func aModelWritesTheReasonAndItsEvidenceIsChecked() {
        let model = FakeModel(fallback: written)
        let result = CardWriter(model: model, modelName: "claude-haiku-5-5").cards(for: Sample.record)
        // The second request is a short answer with no tools: nothing for a model to add.
        #expect(model.requests.count == 1)
        let card = result.cards[0]
        #expect(card.summary == "Tasks expire after three days.")
        #expect(card.why == "Nothing ever left the board.")
        #expect(card.rejected == "A fixed cap." && card.verified == "12 tests pass.")
        // Event 99 isn't in this request, and 4 is named twice.
        #expect(card.evidence == [4, 8])
        #expect(card.source == "claude-haiku-5-5")
        // What git and the chat's structure say is never the model's to change.
        #expect(card.files == ["Sources/Board.swift"] && card.landed == .committed && card.firstEvent == 1 && card.lastEvent == 8)
        #expect(result.cards[1].source == "extract")
    }

    @Test func asksWithTheEventsAndAFixedShape() throws {
        let model = FakeModel(fallback: written)
        _ = CardWriter(model: model).cards(for: Sample.record)
        let request = try #require(model.requests.first)
        #expect(request.model == "claude-haiku-5-5" && request.effort == "low")
        #expect(request.system == CardWriter.instructions)
        #expect(request.user.contains("Repository: acme/widgets"))
        #expect(request.user.contains("[1] USER: The board is slow. Fix it."))
        #expect(request.user.contains("[4] TOOL Edit: Sources/Board.swift\n@@ -1,1 +1,2 @@"))
        #expect(request.user.contains("[6] TOOL Bash (Commit the fix): git commit"))
        #expect(request.user.contains("Commits made: aaaaaaa fix(board): expire finished tasks"))
        // The next request's events aren't this one's business.
        #expect(!request.user.contains("Why three days"))
        let schema = try #require(try JSONSerialization.jsonObject(with: Data(request.schema.utf8)) as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect((schema["required"] as? [String])?.sorted() == ["evidence", "rejected", "summary", "verified", "why"])
    }

    @Test func aFailedAnswerKeepsTheChatsOwnWords() {
        let model = FakeModel(["not json"])
        let result = CardWriter(model: model).cards(for: Sample.record)
        #expect(result.cards[0].source == "extract")
        #expect(result.cards[0].summary.hasPrefix("Finished tasks now expire"))
        #expect(result.failures.count == 1 && result.failures[0].hasPrefix("Request 1:"))

        let refusing = FakeModel()
        refusing.fail("The model declined to answer.")
        #expect(CardWriter(model: refusing).cards(for: Sample.record).failures == ["Request 1: The model declined to answer."])
    }

    @Test func aChatStoredAgainOnlyAsksAboutWhatIsNew() {
        let model = FakeModel(fallback: written)
        var earlier = CardWriter(model: model).cards(for: Sample.record).cards
        #expect(model.requests.count == 1)
        earlier[0].why = "Kept from the first time."

        // The chat picked up again: one more request, with a tool call.
        var grown = Sample.record
        grown.events.append(ChatEvent(n: 11, kind: .user, text: "Now make it five days."))
        grown.events.append(ChatEvent(n: 12, kind: .tool, text: "ls", tool: "Bash"))
        grown.events.append(ChatEvent(n: 13, kind: .agent, text: "Five days it is."))
        let again = FakeModel(fallback: #"{"summary":"Five days.","why":"Asked.","rejected":"","verified":"","evidence":[13]}"#)
        let result = CardWriter(model: again).cards(for: grown, earlier: earlier)
        #expect(again.requests.count == 1)
        #expect(again.requests.first?.user.contains("Now make it five days.") == true)
        #expect(result.cards.map(\.why) == ["Kept from the first time.", "", "Asked."])
        #expect(result.cards[0].source == "claude-haiku-5-5")

        // A request whose events changed is asked about again, and a card taken from the chat's words is never kept.
        var changed = Sample.record
        changed.events.insert(ChatEvent(n: 0, kind: .agent, text: "One more thing."), at: 8)
        for index in changed.events.indices { changed.events[index].n = index + 1 }
        let third = FakeModel(fallback: written)
        _ = CardWriter(model: third).cards(for: changed, earlier: earlier)
        #expect(third.requests.count == 1)
        var extract = earlier
        extract[0].source = "extract"
        let fourth = FakeModel(fallback: written)
        _ = CardWriter(model: fourth).cards(for: Sample.record, earlier: extract)
        #expect(fourth.requests.count == 1)
    }

    @Test func aLongRequestIsCutToFitByDroppingOutputFirst() {
        var record = Sample.record
        record.events[4].text = String(repeating: "noise ", count: 5_000)
        let episode = Episodes.split(record)[0]
        let prompt = CardWriter.prompt(for: episode, in: record, budget: 3_000)
        #expect(prompt.count < 3_600)
        #expect(prompt.contains("let keep = all.filter"))
        #expect(prompt.contains("[1] USER: The board is slow. Fix it."))
        let tiny = CardWriter.prompt(for: episode, in: record, budget: 300)
        #expect(tiny.contains("[the rest is cut]"))
    }

    @Test func asksForEveryRequestWorthAsking() {
        var events: [ChatEvent] = []
        for request in 0..<9 {
            events.append(ChatEvent(n: events.count + 1, kind: .user, text: "Request \(request)"))
            events.append(ChatEvent(n: events.count + 1, kind: .tool, text: "ls", tool: "Bash"))
            events.append(ChatEvent(n: events.count + 1, kind: .agent, text: "Done \(request)."))
        }
        let model = FakeModel(fallback: #"{"summary":"s","why":"w","rejected":"","verified":"","evidence":[]}"#)
        let result = CardWriter(model: model).cards(for: ChatRecord(session: Sample.session, events: events))
        #expect(model.requests.count == 9)
        #expect(result.cards.map(\.episode) == Array(1...9))
        #expect(result.cards.allSatisfy { $0.summary == "s" && $0.why == "w" })
        // With nothing cited, the events the chat itself points at stay.
        #expect(result.cards[0].evidence == [3])
    }
}

@Suite struct ClaudeAPITests {
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func buildsARequestTheAPIAccepts() throws {
        let api = ClaudeAPI(apiKey: "test-key")
        let http = try api.urlRequest(for: ModelRequest(model: "claude-haiku-5-5", system: "S", user: "U", schema: CardWriter.schema))
        #expect(http.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(http.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(http.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(http.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let sent = try body(http)
        #expect(sent["model"] as? String == "claude-haiku-5-5")
        #expect(sent["max_tokens"] as? Int == 4_000)
        // Sampling settings and a thinking budget are rejected by current models, so none are sent.
        #expect(Set(sent.keys) == ["model", "max_tokens", "system", "messages", "output_config"])
        let config = try #require(sent["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "low")
        #expect((config["format"] as? [String: Any])?["type"] as? String == "json_schema")
        #expect(((config["format"] as? [String: Any])?["schema"] as? [String: Any])?["type"] as? String == "object")
        let system = try #require((sent["system"] as? [[String: Any]])?.first)
        #expect(system["text"] as? String == "S")
        #expect((system["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
        #expect(((sent["messages"] as? [[String: Any]])?.first)?["content"] as? String == "U")
    }

    @Test func letsTheAPIHandARefusalToAnotherModelWhereItCan() throws {
        let http = try ClaudeAPI(apiKey: "k").urlRequest(for: ModelRequest(model: "claude-opus-5-5", system: "S", user: "U", schema: "{}"))
        #expect(http.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(try body(http)["fallbacks"] as? String == "default")
        #expect(throws: HistoryError.self) {
            try ClaudeAPI(apiKey: "k").urlRequest(for: ModelRequest(model: "m", system: "S", user: "U", schema: "not json"))
        }
    }

    @Test func readsTheAnswerOutOfAReply() throws {
        let reply = #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"a\":"},{"type":"text","text":"1}"}]}"#
        #expect(try ClaudeAPI.text(from: Data(reply.utf8), status: 200) == #"{"a":1}"#)
    }

    @Test(arguments: [
        (#"{"stop_reason":"refusal","content":[{"type":"text","text":"no"}]}"#, 200, "declined"),
        (#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{"}]}"#, 200, "cut off"),
        (#"{"stop_reason":"end_turn","content":[]}"#, 200, "empty"),
        (#"{"type":"error","error":{"type":"invalid_request_error","message":"bad schema"}}"#, 400, "400: bad schema"),
        ("<html>", 200, "no content"),
    ])
    func turnsABadReplyIntoAnError(_ reply: String, _ status: Int, _ expected: String) {
        #expect { try ClaudeAPI.text(from: Data(reply.utf8), status: status) } throws: { "\($0)".contains(expected) }
    }

    @Test func triesAgainWhenTheAPIIsOverloaded() throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        var api = ClaudeAPI(apiKey: "k", send: { _ in
            counter.calls += 1
            if counter.calls == 1 { return (Data("{}".utf8), 529) }
            return (Data(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}"#.utf8), 200)
        })
        api.retryDelay = 0
        #expect(try api.answer(ModelRequest(model: "claude-haiku-5-5", system: "S", user: "U", schema: "{}")) == "ok")
        #expect(counter.calls == 2)
        let broken = ClaudeAPI(apiKey: "k", send: { _ in
            counter.calls += 1
            return (Data(#"{"error":{"message":"no such model"}}"#.utf8), 404)
        })
        counter.calls = 0
        #expect(throws: HistoryError.self) { try broken.answer(ModelRequest(model: "x", system: "S", user: "U", schema: "{}")) }
        // A request that is wrong stays wrong: it isn't sent again.
        #expect(counter.calls == 1)
    }

    @Test func aKeyInTheEnvironmentIsUsedWithoutAskingTheKeychain() {
        #expect(ClaudeAPI.fromKeychain(environment: ["ANTHROPIC_API_KEY": "  from-env \n"])?.apiKey == "from-env")
    }
}

@Suite struct StoreTests {
    @Test func namesAChatsFolderByRepositoryDayAndSession() {
        #expect(HistoryKeys.folder(for: Sample.session) == "acme/widgets/sessions/2026/11/18/claude-11111111-2222-3333-4444-555555555555/")
        #expect(HistoryKeys.repoPrefix("acme/widgets") == "acme/widgets/sessions/")
        var odd = Sample.session
        odd.repo = "../we ird/..//Name"
        odd.id = "a b/c"
        #expect(HistoryKeys.folder(for: odd) == "we-ird/Name/sessions/2026/11/18/claude-a-b/c/")
        #expect(HistoryKeys.clean("///") == "unknown")
    }

    @Test func aFolderStoresListsAndNoticesChanges() throws {
        let scratch = try Scratch()
        let store = FolderStore(root: scratch.path + "/")
        #expect(try store.get("a/b/c.json") == nil)
        #expect(try store.list(prefix: "a/").isEmpty)
        try store.put(Data("one".utf8), key: "a/b/c.json", contentType: "application/json")
        try store.put(Data("two".utf8), key: "a/d.json", contentType: "application/json")
        try store.put(Data("x".utf8), key: "other/e.json", contentType: "application/json")
        #expect(try store.get("a/b/c.json") == Data("one".utf8))
        let listed = try store.list(prefix: "a/")
        #expect(listed.map(\.key) == ["a/b/c.json", "a/d.json"])
        try store.put(Data("longer".utf8), key: "a/b/c.json", contentType: "application/json")
        #expect(try store.list(prefix: "a/").first?.revision != listed.first?.revision)
        #expect(store.address(of: "a/d.json")?.hasPrefix("file://") == true)
        // A folder that has gone away is an error, not an empty store.
        #expect(throws: HistoryError.self) { try FolderStore(root: scratch.path + "/missing").list(prefix: "") }
    }

    @Test func readsABucketAddress() {
        #expect(S3Store.parse("s3://team-history/agent/chats/")?.bucket == "team-history")
        #expect(S3Store.parse("s3://team-history/agent/chats/")?.prefix == "agent/chats")
        #expect(S3Store.parse("s3://team-history")?.prefix == "")
        #expect(S3Store.parse("s3://Bad_Bucket") == nil)
        #expect(S3Store.parse("/a/folder") == nil)
        #expect(S3Store.parse("https://team-history.s3.amazonaws.com") == nil)
    }

    @Test func talksToS3ThroughTheAWSCommand() throws {
        let fake = FakeShell()
        fake.when("aws", containing: "put-object")
        fake.when("aws", containing: "list-objects-v2", reply: """
            [{"k":"agent/acme/widgets/sessions/2026/11/18/claude-1/cards.json","e":"\\"abc\\"","m":"2026-11-18T10:00:00+00:00"},
             {"k":"agent/acme/widgets/sessions/2026/11/18/claude-1/chat.json","e":"\\"def\\"","m":"2026-11-18T10:00:00+00:00"}]
            """)
        fake.when("aws", containing: "get-object", "missing.json", status: 254, stderr: "An error occurred (NoSuchKey) when calling the GetObject operation")
        fake.when("aws", containing: "get-object", "denied.json", status: 254, stderr: "An error occurred (AccessDenied)")
        let store = S3Store(bucket: "team-history", prefix: "/agent/", region: "eu-north-1", profile: "ocean", shell: fake.shell)

        try store.put(Data("{}".utf8), key: "acme/widgets/x.json", contentType: "application/json")
        let put = try #require(fake.calls.first)
        #expect(put.arguments.prefix(6) == ["s3api", "put-object", "--bucket", "team-history", "--key", "agent/acme/widgets/x.json"])
        #expect(put.arguments.suffix(6) == ["--content-type", "application/json", "--region", "eu-north-1", "--profile", "ocean"])

        let listed = try store.list(prefix: "acme/widgets/sessions/")
        // Keys come back without the store's own prefix, as they were given.
        #expect(listed.map(\.key) == ["acme/widgets/sessions/2026/11/18/claude-1/cards.json", "acme/widgets/sessions/2026/11/18/claude-1/chat.json"])
        #expect(listed[0].revision == "\"abc\"@2026-11-18T10:00:00+00:00")
        #expect(fake.calls[1].arguments.contains("agent/acme/widgets/sessions/"))

        #expect(try store.get("missing.json") == nil)
        #expect { try store.get("denied.json") } throws: { "\($0)".contains("AccessDenied") }
        #expect(store.address(of: "acme/widgets/a b.html") == "https://s3.console.aws.amazon.com/s3/object/team-history?region=eu-north-1&prefix=agent/acme/widgets/a%20b.html")
    }

    @Test func anEmptyBucketListsNothingAndAMissingToolSaysSo() throws {
        let fake = FakeShell()
        fake.when("aws", containing: "list-objects-v2", reply: "null\n")
        fake.when("aws", containing: "put-object", status: 127, stderr: "aws: command not found")
        let store = S3Store(bucket: "team-history", region: "us-east-1", shell: fake.shell)
        #expect(try store.list(prefix: "x/").isEmpty)
        #expect(!fake.calls[0].arguments.contains("--profile"))
        #expect { try store.put(Data(), key: "k", contentType: "t") } throws: { "\($0)".contains("brew install awscli") }
    }
}

@Suite struct ConfigTests {
    @Test func savesAndLoadsWithDefaultsForWhatIsMissing() throws {
        let scratch = try Scratch()
        let url = scratch.url.appendingPathComponent("nested/history.json")
        #expect(HistoryConfig.load(from: url) == HistoryConfig())
        var config = HistoryConfig()
        config.repos["acme/widgets"] = .init(store: "s3://team-history/agent", region: "eu-north-1", profile: nil,
                                             postLinks: true, since: Sample.at(0))
        config.idleHours = 6
        try config.save(to: url)
        #expect(HistoryConfig.load(from: url) == config)
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)

        try Data(#"{"repos":{"a/b":{"store":"/tmp/x"}}}"#.utf8).write(to: url)
        let sparse = HistoryConfig.load(from: url)
        #expect(sparse.repos["a/b"]?.postLinks == true && sparse.repos["a/b"]?.since == nil)
        #expect(sparse.idleHours == 24 && sparse.useModel && sparse.cardModel == "claude-haiku-5-5" && sparse.answerModel == "claude-opus-5-5")
        try Data("garbage".utf8).write(to: url)
        #expect(HistoryConfig.load(from: url) == HistoryConfig())
    }

    @Test func picksTheStoreARepositoryIsSetUpWith() {
        var config = HistoryConfig()
        config.repos["a/s3"] = .init(store: "s3://team-history/agent", region: "eu-north-1")
        config.repos["a/noregion"] = .init(store: "s3://team-history")
        config.repos["a/folder"] = .init(store: "/srv/history")
        config.repos["a/relative"] = .init(store: "history")
        #expect((config.store(for: "a/s3") as? S3Store)?.prefix == "agent")
        #expect(config.store(for: "a/noregion") == nil)
        #expect((config.store(for: "a/folder") as? FolderStore)?.root == "/srv/history")
        #expect(config.store(for: "a/relative") == nil)
        #expect(config.store(for: "a/unknown") == nil)
    }

    @Test func aTranscriptIsCapturedAgainOnlyWhenItGrew() {
        var ledger = CaptureLedger()
        let file = TranscriptFile(sessionID: "s1", path: "/p/s1.jsonl", modified: Sample.at(0), size: 100)
        #expect(ledger.isStale(file, agent: "claude"))
        ledger.captured["claude:s1"] = .init(size: 100, modified: Sample.at(0.4), capturedAt: Sample.at(5), repo: "a/b", folder: "f/")
        #expect(!ledger.isStale(file, agent: "claude"))
        #expect(ledger.isStale(TranscriptFile(sessionID: "s1", path: "/p/s1.jsonl", modified: Sample.at(60), size: 100), agent: "claude"))
        #expect(ledger.isStale(TranscriptFile(sessionID: "s1", path: "/p/s1.jsonl", modified: Sample.at(0), size: 101), agent: "claude"))
        #expect(ledger.isStale(file, agent: "codex"))
    }
}
