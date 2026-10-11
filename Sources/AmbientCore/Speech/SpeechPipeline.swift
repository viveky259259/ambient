import Foundation

/// Speaks chunks in order, synthesizing chunk n+1 while chunk n plays so there's no gap between them.
public enum SpeechPipeline {
    /// Stops at the first synthesis error, which it rethrows. When the calling task is cancelled it throws
    /// `CancellationError` and plays nothing more, even if a chunk finished synthesizing at that moment.
    public static func run<Audio: Sendable>(_ chunks: [String],
                                            synthesize: @escaping @Sendable (String) async throws -> Audio,
                                            play: (Audio) async -> Void) async throws {
        var pending: Task<Audio, Error>?
        defer { pending?.cancel() }
        func start(_ i: Int) -> Task<Audio, Error>? {
            guard chunks.indices.contains(i) else { return nil }
            let text = chunks[i]
            return Task { try await synthesize(text) }
        }
        pending = start(0)
        var i = 0
        while let current = pending {
            let audio = try await withTaskCancellationHandler {
                try await current.value
            } onCancel: {
                current.cancel()
            }
            try Task.checkCancellation()
            i += 1
            pending = start(i)
            await play(audio)
            try Task.checkCancellation()
        }
    }
}
