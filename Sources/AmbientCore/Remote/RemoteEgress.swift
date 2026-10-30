import Foundation

/// Where text from a remote session may go on the hub (ER-13). It came from the user's other machines, under their
/// own transport, so it stays on this Mac: never an online voice, never `skill-bootstrap`, never a non-loopback URL.
public enum RemoteEgress {
    public enum Destination: Equatable, Sendable {
        /// The board's summarizer, at this endpoint.
        case localLLM(URL)
        case onlineVoice
        case skillBootstrap
        case url(URL)
    }

    /// `remoteSummaries` is the separate opt-in for the local LLM; it never widens anything else.
    public static func allows(_ session: Session, to destination: Destination, remoteSummaries: Bool) -> Bool {
        guard session.isRemote else { return true }
        switch destination {
        case let .localLLM(url): return remoteSummaries && TaskLLMConfig.isLoopback(url)
        case .onlineVoice, .skillBootstrap: return false
        case let .url(url): return TaskLLMConfig.isLoopback(url)
        }
    }
}
