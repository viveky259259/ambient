import Foundation

/// Tool names as agents report them, and the short forms Ambient shows.
public enum ToolNames {
    private static let aliases: [String: String] = [
        // Gemini CLI
        "run_shell_command": "Shell",
        "read_file": "Read",
        "read_many_files": "Read",
        "write_file": "Write",
        "replace": "Edit",
        "glob": "Glob",
        "search_file_content": "Grep",
        "list_directory": "List",
        "web_fetch": "Fetch",
        "google_web_search": "Search",
        "save_memory": "Memory",
        // Codex
        "apply_patch": "Patch",
        "shell": "Shell",
        "exec_command": "Shell",
        "local_shell": "Shell",
        "update_plan": "Plan",
        "web_search": "Search",
        // Copilot CLI
        "bash": "Shell",
        "view": "Read",
        "create": "Write",
        "edit": "Edit",
        // OpenCode
        "read": "Read",
        "write": "Write",
        "grep": "Grep",
        "webfetch": "Fetch",
        "websearch": "Search",
        "codesearch": "Search",
        "list": "List",
        "todowrite": "Plan",
        "task": "Task",
        // OpenCode 2
        "subagent": "Task",
        "question": "Question",
        // Antigravity
        "run_command": "Shell",
        "view_file": "Read",
        "write_to_file": "Write",
        "replace_file_content": "Edit",
        "multi_replace_file_content": "Edit",
        "grep_search": "Grep",
        "find_by_name": "Glob",
        "list_dir": "List",
        "read_url_content": "Fetch",
        "search_web": "Search",
    ]

    /// "mcp__github__create_pr" → "github · create_pr"; "run_shell_command" → "Shell".
    public static func display(_ name: String) -> String {
        if name.hasPrefix("mcp__") {
            let parts = name.dropFirst(5).components(separatedBy: "__")
            if parts.count >= 2 { return "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" }
        }
        return aliases[name] ?? name
    }
}
