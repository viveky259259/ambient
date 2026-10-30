import AmbientCore
import Foundation

/// Shared working memory for `ambient memory` and `ambient mcp`: turns what an agent asks into requests to the
/// app, and replies into something to show it.
struct MemoryClient {
    let paths: AmbientPaths
    let request: (WireMessage) -> WireMessage?

    /// The project whose memory is the default: the one around `folder`, or around the folder the agent runs in.
    func project(_ folder: String?) -> String {
        let folder = folder.flatMap { $0.isEmpty ? nil : Commands.absolute($0) }
        return MemoryProject.root(for: folder ?? workingFolder())
    }

    /// Where this process runs, unless that says nothing about the project: some apps start MCP servers in / or the
    /// home folder. Then the folder of the session that started it, which Ambient knows from its hooks.
    private func workingFolder() -> String {
        let cwd = FileManager.default.currentDirectoryPath
        guard cwd == "/" || cwd == paths.userHome.path, case let .status(sessions, _)? = request(.statusRequest),
              let session = Session.calling(callerPids: ProcessTree.ancestors(of: getpid()).map(\.pid), in: sessions),
              let folder = session.cwd else { return cwd }
        return folder
    }

    /// "project", "global", or nothing for the default.
    static func scope(_ name: String?, project: String) throws -> MemoryScope? {
        switch name?.lowercased() {
        case nil, "": nil
        case "project": .project(project)
        case "global": .global
        case let other?: throw MemoryError("Unknown scope '\(other)'. Use project or global.")
        }
    }

    func send(_ message: MemoryRequest) -> MemoryReply {
        guard case let .memoryReply(reply)? = request(.memory(message)) else {
            return .failed("Ambient isn't running. Open Ambient.app, then try again.")
        }
        return reply
    }

    /// Shares text, or a file copied into the blob store first.
    func write(key: String, value: String?, filePath: String?, description: String?, scope: String?,
               ttlMinutes: Int?, untilSessionEnds: Bool, folder: String?) -> MemoryReply {
        let project = project(folder)
        do {
            if let problem = MemoryStore.problem(withKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? value.flatMap(MemoryStore.problem(withValue:)) {
                throw MemoryError(problem)
            }
            let scope = try Self.scope(scope, project: project) ?? .project(project)
            let file = try filePath.map { try MemoryBlobStore(root: paths.memoryBlobs).add(fileAt: Commands.absolute($0)) }
            // Clipped here as well as in the store, so the message always fits through the socket.
            let write = MemoryWrite(key: key, scope: scope, value: value, file: file,
                                    description: Trim.clean(description, max: MemoryStore.maxDescriptionLength),
                                    ttlMinutes: ttlMinutes, untilSessionEnds: untilSessionEnds)
            return send(.write(write, callerPids: ProcessTree.ancestors(of: getpid()).map(\.pid)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func read(key: String, scope: String?, folder: String?) -> MemoryReply {
        let project = project(folder)
        do { return send(.read(key: key, project: project, scope: try Self.scope(scope, project: project))) }
        catch { return .failed(error.localizedDescription) }
    }

    func list(scope: String?, folder: String?) -> MemoryReply {
        let project = project(folder)
        do { return send(.list(project: project, scope: try Self.scope(scope, project: project))) }
        catch { return .failed(error.localizedDescription) }
    }

    func forget(key: String, scope: String?, folder: String?) -> MemoryReply {
        let project = project(folder)
        do { return send(.forget(key: key, project: project, scope: try Self.scope(scope, project: project))) }
        catch { return .failed(error.localizedDescription) }
    }

    /// A few lines on what's shared for the project the agent runs in, for `ambient mcp`'s instructions. Keys and
    /// plain facts only: agents trust instructions, so nothing another agent worded goes in. Keys can't hold a
    /// sentence, and descriptions wait for memory_list, whose results are treated as data.
    func digest(limit: Int = 8, now: Date = Date()) -> String? {
        guard case let .entries(entries) = list(scope: nil, folder: nil), !entries.isEmpty else { return nil }
        var lines = entries.prefix(limit).map { e in
            "- \(e.key) (\(e.scope == .global ? "global" : "project"), \(e.file == nil ? "text" : "file"), "
                + "\(Self.age(e.updatedAt, now: now)))"
        }
        if entries.count > limit { lines.append("- …and \(entries.count - limit) more; memory_list shows them all.") }
        return lines.joined(separator: "\n")
    }

    /// An entry as JSON-ready fields: what an agent needs to use it, and where it came from.
    func fields(_ e: MemoryEntry, now: Date = Date()) -> [String: Any] {
        var object: [String: Any] = [
            "key": e.key,
            "scope": e.scope == .global ? "global" : "project",
            "updated": Self.age(e.updatedAt, now: now),
            "size": e.size,
        ]
        if case let .project(root) = e.scope { object["project"] = root }
        if let value = e.value { object["value"] = value }
        if let file = e.file { object["file"] = MemoryBlobStore(root: paths.memoryBlobs).url(for: file).path }
        if let description = e.description { object["description"] = description }
        if let author = e.author { object["shared_by"] = "\(author.label) (\(author.sessionID))" }
        if e.untilSessionEnds { object["until_session_ends"] = true }
        if let expires = e.expiresAt { object["expires"] = ISO8601DateFormatter().string(from: expires) }
        return object
    }

    static func age(_ date: Date, now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86400: return "\(seconds / 3600) h ago"
        default: return "\(seconds / 86400) d ago"
        }
    }
}
