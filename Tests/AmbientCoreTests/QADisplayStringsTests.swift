import Foundation
import Testing
@testable import AmbientCore

/// User-facing names, messages and defaults: a rename here shows in Settings, so each is pinned.
@Suite struct QADisplayStringsTests {
    @Test func sceneKindNames() {
        #expect(SceneKind.allCases.map(\.displayName) == ["Sky", "Harbor", "Garden", "Solar System"])
    }

    @Test func shortcutProblemMessages() {
        #expect(Shortcut.Problem.needsControlOrOption.message.contains("⌃ or ⌥"))
        #expect(Shortcut.Problem.typesCharacter.message.hasPrefix("⌥ with that key types a character"))
        #expect(Shortcut.Problem.needsControlOrOption.message != Shortcut.Problem.typesCharacter.message)
    }

    @Test func shortcutDisplayOrdersModifiersLikeMenus() {
        let all = Shortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control], key: "A")
        #expect(all.display == "⌃⌥⇧⌘A")
        #expect(Shortcut.optionEscape.display == "⌥⎋")
        #expect(Shortcut.controlOptionV.display == "⌃⌥V")
        #expect(Shortcut.default(systemSpeakSelectionOn: true) == .controlOptionS)
        #expect(Shortcut.default(systemSpeakSelectionOn: false) == .optionEscape)
    }

    @Test func speechEngineNames() {
        #expect(SpeechEngineKind.allCases.map(\.displayName) == ["Mac voice", "Offline model", "Online model"])
    }

    @Test func onlineProviderDefaults() {
        #expect(OnlineProvider.allCases.map(\.displayName) == ["OpenAI", "ElevenLabs", "Your server"])
        #expect(OnlineProvider.openAI.defaultVoice == "alloy")
        #expect(OnlineProvider.elevenLabs.defaultVoice == "21m00Tcm4TlvDq8ikWAM")
        #expect(OnlineProvider.custom.defaultVoice == "af_heart")
        #expect(OnlineProvider.openAI.defaultModel == "gpt-4o-mini-tts")
        #expect(OnlineProvider.elevenLabs.defaultModel == "eleven_flash_v2_5")
        #expect(OnlineProvider.custom.defaultModel == "kokoro")
        #expect(OnlineProvider.allCases.filter(\.needsKey) == [.openAI, .elevenLabs])
    }

    @Test func everyProviderHasANonEmptyVoiceAndModel() {
        for p in OnlineProvider.allCases {
            #expect(!p.defaultVoice.isEmpty)
            #expect(!p.defaultModel.isEmpty)
        }
    }

    @Test func petSpeciesNamesAndStoredFallback() {
        #expect(PetSpecies.allCases.map(\.displayName) == ["Blob", "Crab", "Cat"])
        #expect(PetSpecies(stored: "crab") == .crab)
        #expect(PetSpecies(stored: "dragon") == .blob)
        #expect(PetSpecies(stored: nil) == .blob)
        #expect(PetSpecies(stored: "") == .blob)
    }

    @Test func petExpressionPerPose() {
        #expect(PetArt.expression(for: .sleeping) == .closed)
        #expect(PetArt.expression(for: .working) == .open)
        #expect(PetArt.expression(for: .waiting) == .wide)
        #expect(PetArt.expression(for: .done) == .happy)
        #expect(PetArt.expression(for: .error) == .dizzy)
        // Every pose looks different.
        #expect(Set(PetPose.allCases.map { "\(PetArt.expression(for: $0))" }).count == PetPose.allCases.count)
    }

    @Test func pixelPointDescriptionAndSprites() {
        #expect(PixelPoint(3, -1).description == "(3, -1)")
        let sprite = PixelSprite([".o", "b."])
        #expect(sprite.width == 2 && sprite.height == 2)
        #expect(sprite.pixel(x: 1, y: 0) == "o")
        #expect(sprite.pixel(x: 0, y: 0) == nil)
        #expect(sprite.pixel(x: 5, y: 0) == nil)
        #expect(sprite.pixel(x: 0, y: -1) == nil)
        #expect(PixelSprite([]).width == 0)
    }

    @Test func everySpeciesHasTwoFramesThatFitTheCanvas() {
        for species in PetSpecies.allCases {
            let frames = PetArt.frames(species)
            #expect(frames.count == 2)
        }
    }

    @Test func secretStoreErrorDescriptions() {
        #expect(SecretStoreError.keychain(-25300).errorDescription == "Couldn't talk to the Keychain (-25300).")
        #expect(SecretStoreError.missingAnthropicKey.errorDescription?.contains(SecretStore.service) == true)
        #expect(SecretStoreError.missingAnthropicKey.errorDescription?.contains("ANTHROPIC_API_KEY") == true)
        #expect(SecretStoreError.anthropicHTTP(401, "unauthorized").errorDescription == "Anthropic HTTP 401: unauthorized")
        #expect(SecretStoreError.decode("bad").errorDescription == "bad")
        let long = String(repeating: "e", count: 1_000)
        #expect((SecretStoreError.anthropicHTTP(500, long).errorDescription?.count ?? 0) < 300)
    }

    @Test func secretStoreUsesTheAppsService() {
        #expect(SecretStore.service == "com.viveky259259.Ambient")
        #expect(SecretStore.Account.anthropic.rawValue == "anthropic")
    }
}
