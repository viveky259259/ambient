import Foundation
import Testing
@testable import AmbientCore

private actor Events {
    var items: [String] = []
    func add(_ s: String) { items.append(s) }
    func has(_ s: String) -> Bool { items.contains(s) }
}

private final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Error>?
}

private struct Boom: Error {}

@Suite struct SpeechPipelineTests {
    @Test func playsInOrder() async throws {
        let events = Events()
        try await SpeechPipeline.run(["a", "b", "c"], synthesize: { $0 }, play: { await events.add("play:\($0)") })
        #expect(await events.items == ["play:a", "play:b", "play:c"])
    }

    @Test func preparesTheNextChunkWhileOnePlays() async throws {
        let events = Events()
        try await SpeechPipeline.run(["a", "b"], synthesize: { text in
            await events.add("synth:\(text)")
            return text
        }, play: { audio in
            if audio == "a" {
                for _ in 0..<200 where !(await events.has("synth:b")) { try? await Task.sleep(nanoseconds: 5_000_000) }
            }
            await events.add("play:\(audio)")
        })
        #expect(await events.items == ["synth:a", "synth:b", "play:a", "play:b"])
    }

    @Test func stopsAtTheFirstError() async {
        let events = Events()
        await #expect(throws: Boom.self) {
            try await SpeechPipeline.run(["a", "b", "c"], synthesize: { text in
                if text == "b" { throw Boom() }
                return text
            }, play: { await events.add("play:\($0)") })
        }
        #expect(await events.items == ["play:a"])
    }

    @Test func cancelDuringPlayStopsEverything() async {
        let events = Events()
        let box = TaskBox()
        let task = Task {
            try await SpeechPipeline.run(["a", "b", "c"], synthesize: { text in
                await events.add("synth:\(text)")
                return text
            }, play: { audio in
                await events.add("play:\(audio)")
                while box.task == nil { await Task.yield() }
                box.task?.cancel()
            })
        }
        box.task = task
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        let items = await events.items
        #expect(items.filter { $0.hasPrefix("play:") } == ["play:a"])
        #expect(!items.contains("synth:c"))
    }

    @Test func nothingToSay() async throws {
        let events = Events()
        try await SpeechPipeline.run([], synthesize: { $0 }, play: { await events.add("play:\($0)") })
        #expect(await events.items.isEmpty)
    }
}
