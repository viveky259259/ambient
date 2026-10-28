import Foundation

/// Keeps secrets out of shared memory: whatever one agent shares, every agent on the Mac can read.
public enum MemoryGuard {
    private static let secretPatterns: [(pattern: String, what: String)] = [
        ("-----BEGIN [A-Z ]*PRIVATE KEY-----", "a private key"),
        ("\\bAKIA[0-9A-Z]{16}\\b", "an AWS access key"),
        ("\\bgh[pousr]_[A-Za-z0-9]{36,}", "a GitHub token"),
        ("\\bgithub_pat_[A-Za-z0-9_]{40,}", "a GitHub token"),
        ("\\bglpat-[A-Za-z0-9_-]{20,}", "a GitLab token"),
        ("\\bsk-ant-[A-Za-z0-9_-]{20,}", "an Anthropic API key"),
        ("\\bsk-(proj-)?[A-Za-z0-9_-]{32,}", "an OpenAI API key"),
        ("\\bxox[abposr]-[A-Za-z0-9-]{10,}", "a Slack token"),
        ("\\bAIza[0-9A-Za-z_-]{35}\\b", "a Google API key"),
        ("\\bnpm_[A-Za-z0-9]{36}\\b", "an npm token"),
    ]

    private static let secretNames: Set<String> = [
        ".env", ".netrc", ".npmrc", ".pypirc", ".git-credentials", "credentials", "credentials.json",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
    ]
    private static let secretExtensions: Set<String> = ["pem", "key", "p12", "pfx", "keychain", "keychain-db"]
    /// `.env.example` and the like are templates, meant to be shared.
    private static let envTemplates: Set<String> = ["example", "sample", "template", "dist"]
    private static let secretFolders = ["/.ssh/", "/.aws/", "/.gnupg/", "/Library/Keychains/"]

    /// Why this text shouldn't be shared, or nil.
    public static func problem(withText text: String) -> String? {
        for (pattern, what) in secretPatterns where text.range(of: pattern, options: .regularExpression) != nil {
            return "That looks like it contains \(what). Every agent on this Mac can read shared memory, so Ambient "
                + "doesn't share secrets. Leave it out, or say where the agent can find it instead."
        }
        return nil
    }

    /// Why the file at `path` shouldn't be shared, judged by its name and folder, or nil.
    public static func problem(withFilePath path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        let isEnv = name == ".env" || (name.hasPrefix(".env.") && !envTemplates.contains(ext))
        let what: String
        if isEnv || secretNames.contains(name) || secretExtensions.contains(ext) {
            what = name
        } else if let folder = secretFolders.first(where: { path.contains($0) }) {
            what = "Anything in ~\(folder.dropLast())"
        } else {
            return nil
        }
        return "\(what) usually holds secrets, and every agent on this Mac can read shared memory, so Ambient "
            + "doesn't share it."
    }
}

/// The folder a project's shared memory belongs to.
public enum MemoryProject {
    /// The repository's root for a folder inside it, with git worktrees mapped to the main checkout so they share
    /// memory. Outside a repository, the folder itself.
    public static func root(for folder: String, fileManager: FileManager = .default) -> String {
        let start = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath).standardizedFileURL
            .resolvingSymlinksInPath().path
        var dir = start
        while true {
            let git = (dir as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return dir }
                // A worktree's .git is a file: "gitdir: /repo/.git/worktrees/<name>".
                if let text = try? String(contentsOfFile: git, encoding: .utf8),
                   let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                    let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    if let range = gitdir.range(of: "/.git/worktrees/") {
                        return URL(fileURLWithPath: String(gitdir[..<range.lowerBound])).standardizedFileURL
                            .resolvingSymlinksInPath().path
                    }
                }
                return dir
            }
            // Paths, not URLs: on older macOS, URL's deletingLastPathComponent() turns "/" into "/..", so a
            // folder outside any repository would be walked up forever.
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return start }
            dir = parent
        }
    }
}
