import CryptoKit
import Foundation

public struct VoicePackFile: Equatable, Sendable {
    /// Where the file goes inside the pack folder.
    public let path: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
}

public struct KokoroVoiceOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let accent: String
}

/// Everything the offline voice downloads, each file pinned by hash. Compiled into the app, so a download can't be
/// swapped for something else.
public struct VoicePackManifest: Equatable, Sendable {
    public enum Support: Equatable, Sendable {
        case supported
        case needsNewerMacOS(Int)
        case needsAppleSilicon
    }

    public let version: String
    /// A zip holding the `ambient-voice` folder.
    public let helper: VoicePackFile
    public let files: [VoicePackFile]
    public let voices: [KokoroVoiceOption]
    public let minimumMacOS: Int
    /// The Developer ID team the helper must be signed by.
    public let teamID: String

    public var isPublished: Bool { helper.sha256.count == 64 }
    public var totalBytes: Int64 { files.reduce(helper.bytes) { $0 + $1.bytes } }
    public var folderName: String { "kokoro-\(version)" }
    public var defaultVoice: String { voices[0].id }

    public func support(osMajor: Int, isAppleSilicon: Bool) -> Support {
        if !isAppleSilicon { return .needsAppleSilicon }
        if osMajor < minimumMacOS { return .needsNewerMacOS(minimumMacOS) }
        return .supported
    }

    /// Kokoro-82M (Apache-2.0) in the MLX layout kokoro-ios loads, from Hugging Face at a fixed commit.
    public static let current: VoicePackManifest = {
        let commit = "e02c9eada7ce7416798af36b190a8a2dd2ecd566"
        func hf(_ path: String, _ sha256: String, _ bytes: Int64) -> VoicePackFile {
            VoicePackFile(path: path,
                          url: URL(string: "https://huggingface.co/prince-canuma/Kokoro-82M/resolve/\(commit)/\(path)")!,
                          sha256: sha256, bytes: bytes)
        }
        let voices: [(id: String, name: String, accent: String, sha256: String)] = [
            ("af_heart", "Heart", "American", "4e40b08984cd84a86b4d07960939bd85bb6b3747dd747b7de48dca3aaeab37ca"),
            ("af_bella", "Bella", "American", "a18024b9332f5ff217c7f604cbe94449a3ca51c3b8d85500e31cd3cbdc4ef6ce"),
            ("af_nicole", "Nicole", "American", "769ee38efeb131196eaab5ed43592b315bba829881d4aee7411872efa6cf05c6"),
            ("am_michael", "Michael", "American", "19a8661430456e2bbf0a68b52fa9b49678bb0fb7418619f868df77921f5aa43c"),
            ("bf_emma", "Emma", "British", "ed92055e1ed96f2a0b4a52b76956dcfd76627bd548c33801743a62c0817dec01"),
            ("bm_george", "George", "British", "a3a6682cde622e7aee35597b91947fa018f78be101a97587a100effe227e5a21"),
        ]
        let version = VoicePackPin.version
        return VoicePackManifest(
            version: version,
            helper: VoicePackFile(
                path: "ambient-voice.zip",
                url: URL(string: "https://github.com/viveky259259/ambient/releases/download/voice-\(version)/ambient-voice-\(version).zip")!,
                sha256: VoicePackPin.helperSHA256, bytes: VoicePackPin.helperBytes),
            files: [hf("kokoro-v1_0.safetensors", "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8", 327_115_152)]
                + voices.map { hf("voices/\($0.id).safetensors", $0.sha256, 522_339) },
            voices: voices.map { KokoroVoiceOption(id: $0.id, name: $0.name, accent: $0.accent) },
            minimumMacOS: 15,
            teamID: "CU3457GT8T")
    }()
}

public enum FileHash {
    /// Lowercase hex SHA-256, read a megabyte at a time.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
