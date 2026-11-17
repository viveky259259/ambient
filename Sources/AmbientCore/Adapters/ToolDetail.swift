import Foundation
import AmbientBase
import AmbientContracts

/// The detail half of `ToolNames`, which reads hook payloads and so stays with the adapters.
extension ToolNames {
    /// A short hint of what the tool is doing: the command, the file, the pattern, the host.
    static func detail(name: String, input: HookPayload?) -> String? {
        guard let input, !name.hasPrefix("mcp__") else { return nil }
        if name == "apply_patch", let patch = input.firstString(["input", "patch", "patchText"]) {
            let files = patchedFiles(patch).map(basename)
            return files.first.map { files.count > 1 ? "\($0) +\(files.count - 1) more" : $0 }
        }
        if let command = input.firstString(["command", "cmd", "CommandLine"]) {
            return Trim.clean(command, max: 80)
        }
        // OpenCode's tools say filePath, and its permission requests filepath.
        if let path = input.firstString(["file_path", "filePath", "filepath", "absolute_path", "notebook_path", "path",
                                         "AbsolutePath", "TargetFile"]) {
            return Trim.clean(basename(path), max: 80)
        }
        if let url = input.firstString(["url", "Url"]) {
            return Trim.clean(URL(string: url)?.host ?? url, max: 80)
        }
        return Trim.clean(input.firstString(["pattern", "query", "description", "prompt", "Query", "Pattern", "toolAction"]), max: 80)
    }

    private static func basename(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func patchedFiles(_ patch: String) -> [String] {
        patch.split(separator: "\n").compactMap { line in
            for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }
}
