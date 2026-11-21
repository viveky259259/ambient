import Foundation

/// `page.html`: a chat as one self-contained page a person can read, with removed lines in red and added lines in
/// green, and an anchor on every event so a card can link to the moment it describes.
public enum HistoryPage {
    public static func render(_ record: ChatRecord, cards: [ChangeCard]) -> String {
        let session = record.session
        var body = ""
        body += "<h1>\(escape(session.title ?? "Agent chat"))</h1>\n"
        body += "<table class=\"meta\">\n"
        func row(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            body += "<tr><td>\(name)</td><td>\(value)</td></tr>\n"
        }
        row("Repository", escape(session.repo))
        row("Branch", session.branch.map(escape))
        row("Agent", escape(session.agent))
        row("Developer", session.developer.map(escape))
        row("Session", "<code>\(escape(session.id))</code>")
        row("When", "\(stamp(session.startedAt)) → \(stamp(session.endedAt)) UTC")
        row("Commits", record.commits.isEmpty ? nil : record.commits.map {
            "<code>\(escape(String($0.sha.prefix(7))))</code> \(escape($0.subject))"
        }.joined(separator: "<br>"))
        body += "</table>\n"
        body += "<p class=\"legend\"><span class=\"add\">+ added</span> <span class=\"del\">- removed</span>"
        if record.uncommitted != nil { body += " · <a href=\"#uncommitted\">uncommitted changes</a>" }
        body += "</p>\n"

        if !cards.isEmpty {
            body += "<h2 class=\"section\">Requests</h2>\n<ol class=\"cards\">\n"
            for card in cards {
                body += "<li><a href=\"#e\(card.firstEvent)\">\(escape(Episodes.clip(firstLine(card.request), 140)))</a>"
                if !card.brief.isEmpty { body += "<div>\(escape(card.brief))</div>" }
                if !card.why.isEmpty { body += "<div><b>Why:</b> \(escape(card.why))</div>" }
                if !card.files.isEmpty {
                    body += "<div class=\"files\">\(card.files.map { "<code>\(escape($0))</code>" }.joined(separator: " "))</div>"
                }
                body += "</li>\n"
            }
            body += "</ol>\n"
        }

        body += "<h2 class=\"section\">Conversation</h2>\n"
        for event in record.events {
            body += block(for: event)
        }
        if let uncommitted = record.uncommitted {
            body += "<h2 class=\"section\" id=\"uncommitted\">Uncommitted changes when the chat was captured</h2>\n"
            body += diffBlock(uncommitted)
        }
        return "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            + "<title>\(escape(session.title ?? "Agent chat"))</title><style>\(style)</style></head>\n<body>\n"
            + body + "</body></html>\n"
    }

    private static func block(for event: ChatEvent) -> String {
        let time = event.at.map { " · \(stamp($0))" } ?? ""
        let who = event.actor.map { " (\(escape($0)))" } ?? ""
        let anchor = "<a class=\"n\" href=\"#e\(event.n)\">#\(event.n)</a>"
        let cut = event.cut.map { "<p class=\"cut\">\($0) more characters were left out.</p>" } ?? ""
        switch event.kind {
        case .user:
            return "<section id=\"e\(event.n)\" class=\"user\"><h3>User\(time) \(anchor)</h3>\(prose(event.text))\(cut)</section>\n"
        case .agent:
            return "<section id=\"e\(event.n)\" class=\"agent\"><h3>Agent\(who)\(time) \(anchor)</h3>\(prose(event.text))\(cut)</section>\n"
        case .system:
            return "<section id=\"e\(event.n)\" class=\"system\"><details><summary>System message\(who)\(time) \(anchor)</summary>"
                + "\(prose(event.text))\(cut)</details></section>\n"
        case .thinking:
            return "<section id=\"e\(event.n)\" class=\"system\"><details><summary>Thinking\(who)\(time) \(anchor)</summary>"
                + "\(prose(event.text))\(cut)</details></section>\n"
        case .tool:
            let changes = (event.touches ?? []).contains { $0.how.changes }
            var html = "<section id=\"e\(event.n)\" class=\"tool\"><h4>\(changes ? "Code change" : "Tool") · "
                + "<code>\(escape(event.tool ?? "tool"))</code>\(who)"
            if let label = event.label { html += " — \(escape(label))" }
            html += "\(time) \(anchor)</h4>"
            if !event.text.isEmpty { html += "<pre>\(lines(event.text, class: ""))</pre>" }
            if let diff = event.diff { html += diffBlock(diff) }
            return html + cut + "</section>\n"
        case .result:
            let label = event.failed == true ? "Result (error)" : "Result"
            return "<section id=\"e\(event.n)\" class=\"result\"><details><summary>\(label) \(anchor)</summary>"
                + "<pre>\(lines(event.text, class: ""))</pre>\(cut)</details></section>\n"
        }
    }

    static func diffBlock(_ diff: String) -> String {
        let rendered = diff.components(separatedBy: "\n").map { line -> String in
            let kind: String
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff --git") || line.hasPrefix("index ") {
                kind = "meta"
            } else if line.hasPrefix("@@") {
                kind = "hunk"
            } else if line.hasPrefix("+") {
                kind = "add"
            } else if line.hasPrefix("-") {
                kind = "del"
            } else {
                kind = ""
            }
            return "<span class=\"l \(kind)\">\(line.isEmpty ? " " : escape(line))</span>"
        }.joined(separator: "\n")
        return "<pre class=\"diff\">\(rendered)</pre>"
    }

    private static func lines(_ text: String, class kind: String) -> String {
        text.components(separatedBy: "\n").map { "<span class=\"l \(kind)\">\($0.isEmpty ? " " : escape($0))</span>" }
            .joined(separator: "\n")
    }

    /// Paragraphs, with fenced code kept as code. Deliberately not a Markdown renderer: nothing in a chat is trusted
    /// to become markup.
    private static func prose(_ text: String) -> String {
        var html = ""
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { html += "<p>\(paragraph.map(escape).joined(separator: "<br>"))</p>" }
            paragraph = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = code {
                    html += "<pre>\(lines(open.joined(separator: "\n"), class: ""))</pre>"
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                paragraph.append(line)
            }
        }
        if let open = code { html += "<pre>\(lines(open.joined(separator: "\n"), class: ""))</pre>" }
        flush()
        return html
    }

    private static func firstLine(_ text: String) -> String {
        String(text.split(separator: "\n", omittingEmptySubsequences: true).first ?? "")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// "2026-11-20 19:02", in UTC.
    public static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static let style = """
        :root{--bg:#fff;--fg:#1f2328;--mut:#59636e;--line:#d1d9e0;--code:#f6f8fa;--add:#dafbe1;--addfg:#116329;\
        --del:#ffebe9;--delfg:#a0111f;--hunk:#ddf4ff;--user:#0969da;--agent:#8250df}
        @media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--mut:#9198a1;--line:#3d444d;\
        --code:#151b23;--add:#12361f;--addfg:#7ee787;--del:#4a1a1d;--delfg:#ffa198;--hunk:#12283f;--user:#58a6ff;\
        --agent:#d2a8ff}}
        body{background:var(--bg);color:var(--fg);font:15px/1.55 -apple-system,system-ui,sans-serif;max-width:1000px;\
        margin:0 auto;padding:24px 16px}
        h1{font-size:24px}h2.section{font-size:18px;margin-top:40px;border-bottom:1px solid var(--line);padding-bottom:6px}
        h3{font-size:15px;margin:28px 0 6px;padding-left:10px;border-left:4px solid var(--line)}
        h4{font-size:13px;font-weight:600;margin:14px 0 4px;color:var(--mut)}
        .user h3{border-color:var(--user);color:var(--user)}.agent h3{border-color:var(--agent);color:var(--agent)}
        pre{background:var(--code);border:1px solid var(--line);border-radius:6px;padding:8px 0;overflow-x:auto;\
        font:12px/1.45 ui-monospace,Menlo,monospace;margin:4px 0}
        .l{display:block;padding:0 12px;white-space:pre;min-width:max-content}
        .add{background:var(--add);color:var(--addfg)}.del{background:var(--del);color:var(--delfg)}
        .hunk{background:var(--hunk);color:var(--mut)}.meta{color:var(--mut);font-weight:600}
        code{background:var(--code);padding:1px 5px;border-radius:4px;font:12.5px ui-monospace,Menlo,monospace}
        table.meta{border-collapse:collapse}table.meta td{border:1px solid var(--line);padding:4px 10px;font-size:13px}
        table.meta td:first-child{color:var(--mut)}
        details{margin:6px 0;color:var(--mut)}summary{cursor:pointer;font-size:13px}
        a{color:var(--user)}a.n{font-weight:400;font-size:12px;color:var(--mut);text-decoration:none}
        .legend{font-size:13px;color:var(--mut)}.legend span{padding:1px 8px;border-radius:4px;font-family:ui-monospace,monospace}
        .cut{font-size:12px;color:var(--mut)}ol.cards li{margin:10px 0}ol.cards div{font-size:13px;color:var(--mut)}
        section:target{outline:2px solid var(--user);outline-offset:4px;border-radius:4px}
        """
}
