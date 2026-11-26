import Foundation
import Security
import Testing
@testable import AmbientBase

/// SecretStore is tested without writing to, deleting from, or reading secret data out of the real Keychain.
///
/// `key(for:)` always asks the Keychain first, so its env-var fallback is only deterministic when no Ambient item exists.
/// `noStoredAnthropicItem` checks that with an attributes-only query (no secret data, so no access prompt); the
/// fallback tests are skipped on a Mac where a key is stored.
private let noStoredAnthropicItem: Bool = {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: SecretStore.service,
        kSecAttrAccount as String: SecretStore.Account.anthropic.rawValue,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &item) == errSecItemNotFound
}()

@Suite("SecretStore")
struct QASecretStoreTests {
    @Test func identifiers() {
        #expect(SecretStore.service == "com.viveky259259.Ambient")
        #expect(SecretStore.Account.anthropic.rawValue == "anthropic")
        #expect(SecretStore.Account(rawValue: "anthropic") == .anthropic)
        #expect(SecretStore.Account(rawValue: "openai") == nil)
    }

    // MARK: Error messages

    @Test func keychainErrorShowsTheStatus() {
        #expect(SecretStoreError.keychain(errSecItemNotFound).errorDescription == "Couldn't talk to the Keychain (-25300).")
        #expect(SecretStoreError.keychain(0).localizedDescription == "Couldn't talk to the Keychain (0).")
    }

    @Test func missingKeyNamesWhereToPutIt() throws {
        let text = try #require(SecretStoreError.missingAnthropicKey.errorDescription)
        #expect(text == "No Anthropic key in Keychain (service com.viveky259259.Ambient, account anthropic) or ANTHROPIC_API_KEY.")
    }

    @Test func httpErrorIncludesCodeAndBody() {
        #expect(SecretStoreError.anthropicHTTP(429, #"{"error":"rate_limited"}"#).errorDescription
            == #"Anthropic HTTP 429: {"error":"rate_limited"}"#)
    }

    @Test func httpErrorBodyIsCollapsedAndCappedAt200Characters() throws {
        let body = "line one\n\n   line two\t" + String(repeating: "x", count: 500)
        let text = try #require(SecretStoreError.anthropicHTTP(500, body).errorDescription)
        let shown = try #require(text.components(separatedBy: "Anthropic HTTP 500: ").last)
        #expect(shown.count == 200)
        #expect(shown.hasPrefix("line one line two x"))
        #expect(shown.hasSuffix("…"))
    }

    @Test func httpErrorWithEmptyBody() {
        #expect(SecretStoreError.anthropicHTTP(0, "").errorDescription == "Anthropic HTTP 0: ")
    }

    @Test func decodeErrorIsThePlainMessage() {
        #expect(SecretStoreError.decode("bad JSON").errorDescription == "bad JSON")
        #expect(SecretStoreError.decode("").errorDescription == "")
    }

    @Test func errorsBridgeToNSError() {
        let error: Error = SecretStoreError.decode("boom")
        #expect((error as NSError).localizedDescription == "boom")
    }

    // MARK: Env-var fallback (only when nothing is stored)

    @Test(.enabled(if: noStoredAnthropicItem, "an Ambient Anthropic key is stored in this Mac's Keychain"))
    func envVarIsUsedAndTrimmed() {
        #expect(SecretStore.key(for: .anthropic, environment: ["ANTHROPIC_API_KEY": "  sk-test-123 \n"]) == "sk-test-123")
        #expect(SecretStore.hasKey(for: .anthropic, environment: ["ANTHROPIC_API_KEY": "sk-test"]))
    }

    @Test(.enabled(if: noStoredAnthropicItem, "an Ambient Anthropic key is stored in this Mac's Keychain"),
          arguments: [[String: String](), ["ANTHROPIC_API_KEY": ""], ["ANTHROPIC_API_KEY": " \n\t "],
                      ["anthropic_api_key": "sk-lowercase-name"], ["OPENAI_API_KEY": "sk-other"]])
    func missingOrBlankEnvMeansNoKey(env: [String: String]) {
        #expect(SecretStore.key(for: .anthropic, environment: env) == nil)
        #expect(!SecretStore.hasKey(for: .anthropic, environment: env))
    }
}
