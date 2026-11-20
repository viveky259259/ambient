import Foundation

/// Leaves a link to a chat on the pull requests that hold its commits: one comment per pull request, kept up to date,
/// with one line per chat. Uses the developer's own `gh`.
public struct PullRequestLinks: Sendable {
    public let shell: Shell
    /// Hidden in the comment so it can be found again and updated instead of repeated.
    static let marker = "<!-- ambient-agent-history -->"

    public init(shell: Shell = .system) {
        self.shell = shell
    }

    /// The pull requests a chat's work is in: the ones its harness recorded, and any holding one of its commits.
    public func pullRequests(for record: ChatRecord, recorded: [RawChat.PullRequest]) -> [Int] {
        let repo = record.session.repo
        var numbers = Set(recorded.filter { $0.repo.caseInsensitiveCompare(repo) == .orderedSame }.map(\.number))
        for commit in record.commits {
            let output = shell("gh", ["api", "repos/\(repo)/commits/\(commit.sha)/pulls", "--jq", ".[].number"])
            guard output.succeeded else { continue }
            numbers.formUnion(output.stdout.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        return numbers.sorted()
    }

    /// One chat's line in the comment. The session id in a hidden tag keys it, so capturing the chat again replaces
    /// its line.
    static func line(for record: ChatRecord, url: String, changes: Int) -> String {
        let session = record.session
        // A chat's title and a developer's name are free text going into a public comment: nothing in them may become
        // a link, a mention that notifies someone, or markup.
        func plain(_ text: String) -> String {
            var cleaned = text.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            for character in ["\n", "\r", "@", "<", ">", "`"] { cleaned = cleaned.replacingOccurrences(of: character, with: " ") }
            return cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }
        let title = plain(session.title ?? "Agent chat")
        let day = HistoryPage.stamp(session.endedAt).prefix(10)
        var parts = ["\(plain(session.agent))", String(day)]
        if let developer = session.developer { parts.append(plain(developer)) }
        parts.append(changes == 1 ? "1 request changed code" : "\(changes) requests changed code")
        return "- [\(title)](\(url)) — \(parts.joined(separator: ", ")) <!-- chat:\(session.agent):\(session.id) -->"
    }

    /// The comment with this chat's line added, or put in place of its earlier one.
    static func body(adding line: String, sessionTag: String, to existing: String?) -> String {
        let header = "\(marker)\n**Agent history** — the chats behind this pull request's commits. "
            + "Each opens for people with access to the team's history store; "
            + "`ambient history why <file>` reads the same record from a checkout.\n"
        var lines = (existing ?? "").components(separatedBy: "\n").filter { $0.hasPrefix("- ") && !$0.contains(sessionTag) }
        lines.append(line)
        return header + "\n" + lines.joined(separator: "\n") + "\n"
    }

    /// Adds or updates the comment on each pull request. Returns the pull requests it wrote to; one it can't reach
    /// is skipped, since a link is a convenience and never a reason to fail a capture.
    @discardableResult
    public func post(for record: ChatRecord, url: String, changes: Int, to numbers: [Int]) -> [Int] {
        let repo = record.session.repo
        let tag = "<!-- chat:\(record.session.agent):\(record.session.id) -->"
        let line = Self.line(for: record, url: url, changes: changes)
        var posted: [Int] = []
        for number in numbers {
            let listed = shell("gh", ["api", "repos/\(repo)/issues/\(number)/comments", "--paginate",
                                      "--jq", ".[] | select(.body | contains(\"\(Self.marker)\")) | \"\\(.id)\\u001f\\(.body)\\u001e\""])
            guard listed.succeeded else { continue }
            let first = listed.stdout.split(separator: "\u{1e}").first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = first?.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let body = Self.body(adding: line, sessionTag: tag, to: fields?.count == 2 ? fields?[1] : nil)
            let payload = (try? JSONSerialization.data(withJSONObject: ["body": body])) ?? Data()
            let output: Shell.Output
            if let fields, fields.count == 2, let id = Int(fields[0]) {
                // Nothing to do when the chat's line is already there, word for word.
                if fields[1].trimmingCharacters(in: .whitespacesAndNewlines) == body.trimmingCharacters(in: .whitespacesAndNewlines) {
                    posted.append(number)
                    continue
                }
                output = shell("gh", ["api", "-X", "PATCH", "repos/\(repo)/issues/comments/\(id)", "--input", "-"], input: payload)
            } else {
                output = shell("gh", ["api", "-X", "POST", "repos/\(repo)/issues/\(number)/comments", "--input", "-"], input: payload)
            }
            if output.succeeded { posted.append(number) }
        }
        return posted
    }
}
