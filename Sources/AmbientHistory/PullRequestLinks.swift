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

    /// One chat's line in the comment. It says when, which agent and how much, and nothing the chat said: the title
    /// is the first thing the person typed, and a pull request may be public. The session id in a hidden tag keys
    /// the line, so capturing the chat again replaces it.
    static func line(for record: ChatRecord, url: String, changes: Int) -> String {
        let session = record.session
        let agent = String(session.agent.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(20))
        let id = String(session.id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(80))
        let day = HistoryPage.stamp(session.endedAt).prefix(10)
        let work = changes == 1 ? "1 request changed code" : "\(changes) requests changed code"
        return "- [\(agent) chat of \(day)](\(url)) — \(work) <!-- chat:\(agent):\(id) -->"
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
        let line = Self.line(for: record, url: url, changes: changes)
        // The tag as the line itself spells it.
        let tag = line.range(of: "<!-- chat:").map { String(line[$0.lowerBound...]) } ?? line
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
