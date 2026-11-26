import Foundation
import Testing
@testable import AmbientCore

@Suite struct VoicePackTests {
    let pack = VoicePackManifest.current

    @Test func everyDownloadIsHTTPSAndPinned() {
        for f in pack.files {
            #expect(f.url.scheme == "https")
            #expect(f.url.absoluteString.contains("/resolve/e02c9eada7ce7416798af36b190a8a2dd2ecd566/"))
            #expect(f.sha256.count == 64)
            #expect(f.bytes > 0)
        }
        #expect(pack.helper.url.absoluteString
                == "https://github.com/viveky259259/ambient/releases/download/voice-\(VoicePackPin.version)/ambient-voice-\(VoicePackPin.version).zip")
    }

    @Test func pathsStayInsideThePack() {
        let paths = ([pack.helper] + pack.files).map(\.path)
        #expect(Set(paths).count == paths.count)
        #expect(paths.allSatisfy { !$0.hasPrefix("/") && !$0.contains("..") })
    }

    @Test func everyVoiceHasItsFile() {
        #expect(pack.voices.first?.id == pack.defaultVoice)
        for v in pack.voices { #expect(pack.files.contains { $0.path == "voices/\(v.id).safetensors" }) }
    }

    @Test func publishedOnlyWithAPinnedHelper() {
        #expect(pack.isPublished == (pack.helper.sha256.count == 64))
        #expect(pack.totalBytes == pack.files.reduce(pack.helper.bytes) { $0 + $1.bytes })
        #expect(pack.folderName == "kokoro-\(VoicePackPin.version)")
    }

    @Test func support() {
        #expect(pack.support(osMajor: 15, isAppleSilicon: true) == .supported)
        #expect(pack.support(osMajor: 14, isAppleSilicon: true) == .needsNewerMacOS(15))
        #expect(pack.support(osMajor: 26, isAppleSilicon: false) == .needsAppleSilicon)
    }

    @Test func hashesAFile() throws {
        let url = try shortTempDir().appendingPathComponent("abc")
        try Data("abc".utf8).write(to: url)
        #expect(try FileHash.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func voiceFolderLivesInAmbientHome() {
        let paths = AmbientPaths(userHome: URL(fileURLWithPath: "/Users/x"))
        #expect(paths.voice.path == "/Users/x/.ambient/voice")
    }
}
