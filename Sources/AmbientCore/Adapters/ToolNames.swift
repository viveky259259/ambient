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
    ]

    /// "mcp__github__create_pr" → "github · create_pr"; "run_shell_command" → "Shell".
    public static func display(_ name: String) -> String {
        if name.hasPrefix("mcp__") {
            let parts = name.dropFirst(5).components(separatedBy: "__")
            if parts.count >= 2 { return "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" }
        }
        return aliases[name] ?? name
    }

    /// A short hint of what the tool is doing: the command, the file, the pattern, the host.
    static func detail(name: String, input: HookPayload?) -> String? {
        guard let input, !name.hasPrefix("mcp__") else { return nil }
        if name == "apply_patch", let patch = input.firstString(["input", "patch"]) {
            return patchedFile(patch).map(basename)
        }
        if let command = input.firstString(["command", "cmd"]) {
            return Trim.clean(command, max: 80)
        }
        if let path = input.firstString(["file_path", "absolute_path", "notebook_path", "path"]) {
            return Trim.clean(basename(path), max: 80)
        }
        if let url = input.string("url") {
            return Trim.clean(URL(string: url)?.host ?? url, max: 80)
        }
        return Trim.clean(input.firstString(["pattern", "query", "description", "prompt"]), max: 80)
    }

    private static func basename(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func patchedFile(_ patch: String) -> String? {
        for line in patch.split(separator: "\n") {
            for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
