import Foundation

/// What a model on disk is, judged only from its files, and so which runtime can run it.
public enum LocalModelFormat: String, Codable, Equatable, Sendable {
    /// `config.json` with safetensors weights: an MLX (or MLX-loadable Hugging Face) text model, run with mlx-lm.
    case mlxText
    /// The same with a `vision_config`: run with mlx-vlm, text only for board summaries.
    case mlxVision
    /// A llama.cpp model file.
    case gguf
    /// Speech, transcription, image or video weights: real models, but they can't write a summary.
    case media
    case unknown

    public var label: String {
        switch self {
        case .mlxText: "MLX text model"
        case .mlxVision: "MLX vision model"
        case .gguf: "GGUF model"
        case .media: "Speech, image or video model"
        case .unknown: "Unrecognized model"
        }
    }

    /// What runs this format directly, without the gateway.
    public var runtime: String? {
        switch self {
        case .mlxText: "mlx-lm"
        case .mlxVision: "mlx-vlm"
        case .gguf: "llama.cpp"
        case .media, .unknown: nil
        }
    }

    public var writesText: Bool { self == .mlxText || self == .mlxVision || self == .gguf }
}

/// A model folder or file the user pointed Ambient at, and what a runtime should load from it.
public struct LocalModelPath: Equatable, Sendable {
    /// What was chosen, with `~` expanded.
    public var requested: String
    /// What a runtime loads: a Hugging Face cache repo resolves to its snapshot, a folder of `.gguf` files to the first.
    public var resolved: String
    public var format: LocalModelFormat
    /// Why `format` is `.unknown`, for the status line.
    public var note: String?

    public var name: String {
        let last = URL(fileURLWithPath: requested).lastPathComponent
        return last.hasPrefix("models--") ? last.dropFirst(8).replacingOccurrences(of: "--", with: "/") : last
    }

    /// Nil when nothing exists at `path`.
    public static func inspect(_ path: String, fileManager fm: FileManager = .default) -> LocalModelPath? {
        let requested = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !requested.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: requested, isDirectory: &isDir) else { return nil }
        let url = URL(fileURLWithPath: requested)
        if !isDir.boolValue {
            let format: LocalModelFormat = url.pathExtension.lowercased() == "gguf" ? .gguf
                : mediaName(url.lastPathComponent) ? .media : .unknown
            return LocalModelPath(requested: requested, resolved: requested, format: format,
                                  note: format == .unknown ? "Choose a model folder or a .gguf file." : nil)
        }
        let folder = snapshot(of: url, fileManager: fm) ?? url
        var model = classify(folder, fileManager: fm)
        model.requested = requested
        return model
    }

    /// A Hugging Face cache repo (`models--org--name`) loads from the snapshot `refs/main` points at.
    static func snapshot(of repo: URL, fileManager fm: FileManager) -> URL? {
        guard repo.lastPathComponent.hasPrefix("models--") else { return nil }
        let snapshots = repo.appendingPathComponent("snapshots", isDirectory: true)
        if let ref = try? String(contentsOf: repo.appendingPathComponent("refs/main"), encoding: .utf8) {
            let pinned = snapshots.appendingPathComponent(ref.trimmingCharacters(in: .whitespacesAndNewlines))
            if fm.fileExists(atPath: pinned.path) { return pinned }
        }
        let all = (try? fm.contentsOfDirectory(atPath: snapshots.path))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
        return all.first.map { snapshots.appendingPathComponent($0, isDirectory: true) }
    }

    private static func classify(_ folder: URL, fileManager fm: FileManager) -> LocalModelPath {
        let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        func made(_ format: LocalModelFormat, _ resolved: URL = folder, note: String? = nil) -> LocalModelPath {
            LocalModelPath(requested: folder.path, resolved: resolved.path, format: format, note: note)
        }
        let parent = folder.deletingLastPathComponent()
        let repo = parent.lastPathComponent == "snapshots" ? parent.deletingLastPathComponent().lastPathComponent : ""
        if mediaName(folder.lastPathComponent) || mediaName(repo) { return made(.media) }
        let config = (try? Data(contentsOf: folder.appendingPathComponent("config.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let config {
            if let type = config["model_type"] as? String, mediaName(type) { return made(.media) }
            guard files.contains(where: { $0.hasSuffix(".safetensors") || $0 == "model.safetensors.index.json" }) else {
                return made(.unknown, note: "No safetensors weights next to config.json; convert it with mlx_lm.convert.")
            }
            return made(config["vision_config"] != nil ? .mlxVision : .mlxText)
        }
        // Split GGUFs load from their first shard; a vision projector (mmproj) isn't the model.
        let ggufs = files.filter { $0.lowercased().hasSuffix(".gguf") && !$0.lowercased().contains("mmproj") }.sorted()
        if let first = ggufs.first {
            return made(.gguf, folder.appendingPathComponent(first))
        }
        return made(.unknown, note: "No config.json or .gguf file in this folder.")
    }

    /// The gateway's own name-based split between text and media models.
    static func mediaName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["whisper", "kokoro", "chatterbox", "ltx", "z-image", "flux", "qwen-image", "s3tokenizer"]
            .contains { lower.contains($0) }
    }
}

/// Finds the runtimes that can run a model on disk directly, when the local-agent gateway doesn't know it.
public enum LocalRuntimes {
    /// Pythons to try for mlx-lm / mlx-vlm, in order: the user's choice, the gateway's own MLX runtime, then
    /// common installs. Duplicates and missing files are dropped.
    public static func pythonCandidates(configured: String, gatewayPythons: [String] = [],
                                        environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let configured = (configured.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        var list: [String] = []
        if !configured.isEmpty { list.append(configured) }
        list += gatewayPythons
        list += searchPath(environment).map { $0 + "/python3" }
        list += ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        var seen = Set<String>()
        return list.filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert($0).inserted }
    }

    /// The first candidate that can import `module`. A user-chosen Python that can't is still the only one tried,
    /// so the status says what's wrong with it instead of quietly running something else.
    public static func python(with module: String, configured: String, gatewayPythons: [String] = []) -> String? {
        let candidates = pythonCandidates(configured: configured, gatewayPythons: gatewayPythons)
        let configured = (configured.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if !configured.isEmpty {
            return candidates.first == configured && canImport(module, python: configured) ? configured : nil
        }
        return candidates.first { canImport(module, python: $0) }
    }

    /// llama.cpp's plain completion tool, or the older `llama-cli` (which then needs `-no-cnv`).
    public static func llamaCpp(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let dirs = searchPath(environment) + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"]
        for tool in ["llama-completion", "llama-cli"] {
            if let hit = dirs.map({ $0 + "/" + tool }).first(where: FileManager.default.isExecutableFile(atPath:)) {
                return hit
            }
        }
        return nil
    }

    private static func searchPath(_ environment: [String: String]) -> [String] {
        (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }

    /// Successful probes only: a runtime installed later is found on the next status check.
    private static let cache = ImportCache()

    static func canImport(_ module: String, python: String) -> Bool {
        let key = python + "\u{0}" + module
        if cache.contains(key) { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('\(module)') else 1)"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return false }
        if finished.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            return false
        }
        guard process.terminationStatus == 0 else { return false }
        cache.insert(key)
        return true
    }

    private final class ImportCache: @unchecked Sendable {
        private let lock = NSLock()
        private var found = Set<String>()
        func contains(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return found.contains(key) }
        func insert(_ key: String) { lock.lock(); defer { lock.unlock() }; found.insert(key) }
    }
}
