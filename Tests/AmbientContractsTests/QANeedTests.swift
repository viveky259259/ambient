import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA Need")
struct QANeedTests {
    @Test(arguments: Need.allCases)
    func everyRawValueReadsBack(need: Need) {
        #expect(Need(reason: need.rawValue) == need)
    }

    @Test(arguments: ["", "Permission", "COMMAND", " command", "command ", "garbage", "needs-you", "\u{0}", "edit\n"])
    func anythingElseIsAQuestion(reason: String) {
        #expect(Need(reason: reason) == .question)
    }

    @Test func rawValues() {
        #expect(Need.allCases.map(\.rawValue) == ["command", "edit", "web", "access", "plan", "question", "permission"])
    }

    @Test(arguments: Need.allCases)
    func onlyQuestionsAreNotPermissions(need: Need) {
        #expect(need.isPermission == (need != .question))
    }

    static let text: [(Need, String, String)] = [
        (.command, "Approve a command", "Approve command"),
        (.edit, "Review a change", "Review change"),
        (.web, "Allow web access", "Allow web access"),
        (.access, "Allow access outside the project", "Allow access"),
        (.plan, "Review a plan", "Review plan"),
        (.question, "Answer a question", "Answer question"),
        (.permission, "Approve a tool", "Approve tool"),
    ]

    @Test(arguments: text)
    func headlineAndShort(need: Need, headline: String, short: String) {
        #expect(need.headline == headline)
        #expect(need.short == short)
        #expect(need.short.count <= need.headline.count)
    }

    @Test func headlinesAreDistinct() {
        #expect(Set(Need.allCases.map(\.headline)).count == Need.allCases.count)
        #expect(Set(Need.allCases.map(\.short)).count == Need.allCases.count)
    }

    static let tools: [(String, Need)] = [
        // Shell, across agents
        ("Bash", .command), ("bash", .command), ("Shell", .command), ("shell", .command),
        ("run_shell_command", .command), ("exec_command", .command), ("local_shell", .command), ("run_command", .command),
        // Edits
        ("Edit", .edit), ("Write", .edit), ("MultiEdit", .edit), ("NotebookEdit", .edit), ("Update", .edit),
        ("apply_patch", .edit), ("Patch", .edit), ("replace", .edit), ("write_file", .edit), ("create", .edit),
        ("edit", .edit), ("write", .edit), ("write_to_file", .edit), ("replace_file_content", .edit),
        ("multi_replace_file_content", .edit),
        // Web
        ("WebFetch", .web), ("WebSearch", .web), ("Web Search", .web), ("Fetch", .web), ("Search", .web),
        ("web_fetch", .web), ("google_web_search", .web), ("web_search", .web), ("webfetch", .web), ("websearch", .web),
        ("codesearch", .web), ("read_url_content", .web), ("search_web", .web),
        // Plans
        ("ExitPlanMode", .plan), ("exit_plan_mode", .plan), ("plan_exit", .plan),
        // Questions
        ("AskUserQuestion", .question), ("Question", .question), ("question", .question), ("ask_user", .question),
        // Everything else
        ("Read", .permission), ("read_file", .permission), ("Glob", .permission), ("Task", .permission),
        ("update_plan", .permission), ("todowrite", .permission), ("mcp__github__create_pr", .permission),
        ("", .permission), ("BASH", .permission), ("exitplanmode", .permission), ("Edit ", .permission),
    ]

    @Test(arguments: tools)
    func needForTool(name: String, need: Need) {
        #expect(Need.forTool(name) == need)
    }

    @Test func namedGivesTheToolOnlyWhenNoNeedFits() {
        #expect(Need.named("Bash") == (.command, nil))
        #expect(Need.named("apply_patch") == (.edit, nil))
        #expect(Need.named("mcp__github__create_pr") == (.permission, "github · create_pr"))
        #expect(Need.named("Read") == (.permission, "Read"))
        #expect(Need.named("read_file") == (.permission, "Read"))
        #expect(Need.named("") == (.permission, ""))
    }

    static let texts: [(String?, Need, String?)] = [
        (nil, .permission, nil),
        ("", .permission, nil),
        ("   \n\t ", .permission, nil),
        ("Claude needs your permission to use Bash", .command, nil),
        ("Claude needs your permission to use Write.", .edit, nil),
        ("Needs PERMISSION TO USE WebFetch?!", .web, nil),
        ("permission to use mcp__github__create_pr", .permission, "github · create_pr"),
        ("permission to use Read", .permission, "Read"),
        ("Bash", .command, nil),
        ("  Edit  ", .edit, nil),
        ("rm", .permission, "rm"),
        ("Allow Bash?", .permission, "Allow Bash?"),
        ("Claude needs your permission", .permission, "Claude needs your permission"),
        ("permission to use ...", .permission, "permission to use ..."),
        ("Do you   want\nto continue?", .permission, "Do you want to continue?"),
    ]

    @Test(arguments: texts)
    func needFromPromptText(text: String?, need: Need, detail: String?) {
        let got = Need.fromText(text)
        #expect(got.need == need)
        #expect(got.detail == detail)
    }

    @Test func longPromptTextIsCutToTheMessageLimit() {
        let got = Need.fromText(String(repeating: "word ", count: 500))
        #expect(got.need == .permission)
        #expect(got.detail?.count == 160)
        #expect(got.detail?.hasSuffix("…") == true)
    }

    @Test func longToolNameAfterThePhraseIsCutToo() {
        let got = Need.fromText("permission to use " + String(repeating: "x", count: 10_000))
        #expect(got.need == .permission)
        #expect((got.detail?.count ?? 0) <= 160)
    }

    @Test func singleHugeWordIsATool() {
        let got = Need.fromText(String(repeating: "a", count: 1_000))
        #expect(got.need == .permission)
        #expect(got.detail?.count == 160)
    }
}
