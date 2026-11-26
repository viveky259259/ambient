import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA ToolNames")
struct QAToolNamesTests {
    static let aliases: [(String, String)] = [
        // Gemini CLI
        ("run_shell_command", "Shell"), ("read_file", "Read"), ("read_many_files", "Read"), ("write_file", "Write"),
        ("replace", "Edit"), ("glob", "Glob"), ("search_file_content", "Grep"), ("list_directory", "List"),
        ("web_fetch", "Fetch"), ("google_web_search", "Search"), ("save_memory", "Memory"),
        // Codex
        ("apply_patch", "Patch"), ("shell", "Shell"), ("exec_command", "Shell"), ("local_shell", "Shell"),
        ("update_plan", "Plan"), ("web_search", "Search"),
        // Copilot CLI
        ("bash", "Shell"), ("view", "Read"), ("create", "Write"), ("edit", "Edit"),
        // OpenCode
        ("read", "Read"), ("write", "Write"), ("grep", "Grep"), ("webfetch", "Fetch"), ("websearch", "Search"),
        ("codesearch", "Search"), ("list", "List"), ("todowrite", "Plan"), ("task", "Task"),
        // OpenCode 2
        ("subagent", "Task"), ("question", "Question"),
        // Antigravity
        ("run_command", "Shell"), ("view_file", "Read"), ("write_to_file", "Write"), ("replace_file_content", "Edit"),
        ("multi_replace_file_content", "Edit"), ("grep_search", "Grep"), ("find_by_name", "Glob"), ("list_dir", "List"),
        ("read_url_content", "Fetch"), ("search_web", "Search"),
    ]

    @Test(arguments: aliases)
    func agentToolNamesNormalize(raw: String, shown: String) {
        #expect(ToolNames.display(raw) == shown)
    }

    @Test(arguments: aliases.map(\.1))
    func normalizedNamesAreFixedPoints(shown: String) {
        // Showing a name twice changes nothing, so code may normalize before or after storing.
        #expect(ToolNames.display(ToolNames.display(shown)) == ToolNames.display(shown))
    }

    @Test(arguments: ["Bash", "Read", "Edit", "WebFetch", "Write", "", "BASH", "Shell ", " shell", "unknown_tool",
                      "工具", "🔧"])
    func unknownOrMiscasedNamesPassThrough(name: String) {
        #expect(ToolNames.display(name) == name)
    }

    @Test(arguments: [
        ("mcp__github__create_pr", "github · create_pr"),
        ("mcp__a__b__c", "a · b__c"),
        ("mcp__server__", "server · "),
        ("mcp____tool", " · tool"),
        ("mcp__only", "mcp__only"),
        ("mcp__", "mcp__"),
        ("mcp_x__y", "mcp_x__y"),
        ("MCP__a__b", "MCP__a__b"),
        ("xmcp__a__b", "xmcp__a__b"),
    ])
    func mcpToolsShowServerAndTool(raw: String, shown: String) {
        #expect(ToolNames.display(raw) == shown)
    }

    @Test func hugeNamesAreNotCut() {
        let name = String(repeating: "a", count: 10_000)
        #expect(ToolNames.display(name) == name)
        #expect(ToolNames.display("mcp__s__" + name) == "s · " + name)
    }
}
