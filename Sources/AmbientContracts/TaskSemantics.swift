import Foundation

/// Structured semantics produced by the local LLM (or parsed from its reply).
public struct TaskSemantics: Equatable, Sendable {
    public var title: String?
    public var summary: String?
    public var status: TaskStatus?

    public init(title: String? = nil, summary: String? = nil, status: TaskStatus? = nil) {
        self.title = title
        self.summary = summary
        self.status = status
    }
}
