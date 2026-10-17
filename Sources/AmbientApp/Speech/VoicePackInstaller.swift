import AmbientCore
import Foundation
import Security

/// Downloads, checks and installs the offline voice, and removes it. Nothing reaches the pack folder unless every
/// hash matched and the helper is signed by Ambient's team. Used from the main thread; the download hops back to it.
final class VoicePackInstaller: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case unsupported(String)
        /// This build has no published helper pinned.
        case unavailable
        case notInstalled
        case downloading(Double)
        case installed
        case failed(String)
    }

    @Published private(set) var status: Status = .notInstalled
    let manifest: VoicePackManifest
    private let paths: AmbientPaths
    private var work: Task<Void, Never>?

    init(paths: AmbientPaths, manifest: VoicePackManifest = .current) {
        self.paths = paths
        self.manifest = manifest
        refresh()
    }

    var folder: URL {
        #if AMBIENT_DEV
        if let dev = ProcessInfo.processInfo.environment["AMBIENT_VOICE_DEV_PACK"] { return URL(fileURLWithPath: dev) }
        #endif
        return paths.voice.appendingPathComponent(manifest.folderName, isDirectory: true)
    }

    var helper: URL {
        #if AMBIENT_DEV
        if let dev = ProcessInfo.processInfo.environment["AMBIENT_VOICE_DEV_HELPER"] { return URL(fileURLWithPath: dev) }
        #endif
        return folder.appendingPathComponent("ambient-voice/ambient-voice")
    }

    var downloadSize: String {
        "≈\(Int((Double(manifest.totalBytes) / 1_000_000).rounded())) MB"
    }

    func refresh() {
        guard work == nil else { return }
        var appleSilicon = false
        #if arch(arm64)
        appleSilicon = true
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        switch manifest.support(osMajor: os, isAppleSilicon: appleSilicon) {
        case .needsAppleSilicon:
            status = .unsupported("The offline model needs a Mac with Apple silicon.")
        case .needsNewerMacOS(let v):
            status = .unsupported("The offline model needs macOS \(v) or later.")
        case .supported:
            if FileManager.default.isExecutableFile(atPath: helper.path) {
                status = .installed
            } else {
                status = manifest.isPublished ? .notInstalled : .unavailable
            }
        }
    }

    func install() {
        guard work == nil, status == .notInstalled || isFailed else { return }
        status = .downloading(0)
        work = Task { [self] in await run() }
    }

    func cancel() {
        work?.cancel()
    }

    /// Called before the pack folder is deleted, so the running helper lets go of the model.
    var onRemove: () -> Void = {}

    func remove() {
        cancel()
        onRemove()
        try? FileManager.default.removeItem(at: paths.voice.appendingPathComponent(manifest.folderName))
        refresh()
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private func run() async {
        let fm = FileManager.default
        let staging = paths.voice.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let total = Double(manifest.totalBytes)
            var done: Int64 = 0
            for file in [manifest.helper] + manifest.files {
                let destination = staging.appendingPathComponent(file.path)
                let base = done
                try await FileDownload.run(file.url, to: destination) { [weak self] written in
                    let fraction = min(1, Double(base + written) / total)
                    DispatchQueue.main.async { self?.status = .downloading(fraction) }
                }
                guard try FileHash.sha256(of: destination) == file.sha256 else {
                    throw SpeechFailure(message: "A downloaded file didn't match, so nothing was installed. Try again.")
                }
                done += file.bytes
            }
            let zip = staging.appendingPathComponent(manifest.helper.path)
            try Self.unzip(zip, into: staging)
            try fm.removeItem(at: zip)
            try Self.verifySignature(staging.appendingPathComponent("ambient-voice/ambient-voice"), team: manifest.teamID)
            let target = paths.voice.appendingPathComponent(manifest.folderName, isDirectory: true)
            // On the main thread, where remove() and cancel() run: a Remove or Cancel that came first wins, and the
            // pack is never moved into place after it.
            try await MainActor.run {
                try Task.checkCancellation()
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: staging, to: target)
            }
            await MainActor.run { self.work = nil; self.refresh() }
        } catch is CancellationError {
            await MainActor.run { self.work = nil; self.refresh() }
        } catch {
            let message = (error as? SpeechFailure)?.message ?? "The download failed: \(error.localizedDescription)"
            await MainActor.run { self.work = nil; self.status = .failed(message) }
        }
    }

    private static func unzip(_ zip: URL, into folder: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, folder.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw SpeechFailure(message: "Couldn't unpack the offline voice.") }
    }

    private static func verifySignature(_ url: URL, team: String) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
                                         requirement) == errSecSuccess else {
            throw SpeechFailure(message: "The offline voice's signature didn't check out, so nothing was installed.")
        }
    }
}
