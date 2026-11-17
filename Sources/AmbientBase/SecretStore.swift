import Foundation
import Security

/// Login-Keychain secrets for Ambient (never files under Sources/, never Preferences).
///
/// Anthropic is **bootstrap-only** (skill pack generation). Live board summaries stay on local-agent MCP.
public enum SecretStore {
    public static let service = "com.viveky259259.Ambient"

    public enum Account: String, Sendable {
        case anthropic
    }

    /// Reads a secret: Keychain first, then `ANTHROPIC_API_KEY` env for the anthropic account.
    public static func key(for account: Account,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let stored = keychainKey(for: account), !stored.isEmpty { return stored }
        if account == .anthropic {
            let env = environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let env, !env.isEmpty { return env }
        }
        return nil
    }

    public static func setKey(_ key: String, for account: Account) throws {
        deleteKey(for: account)
        guard !key.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.keychain(status)
        }
    }

    public static func deleteKey(for account: Account) {
        SecItemDelete(query(account) as CFDictionary)
    }

    public static func hasKey(for account: Account,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        key(for: account, environment: environment) != nil
    }

    private static func query(_ account: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.rawValue]
    }

    private static func keychainKey(for account: Account) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum SecretStoreError: Error, LocalizedError, Sendable {
    case keychain(OSStatus)
    case missingAnthropicKey
    case anthropicHTTP(Int, String)
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case let .keychain(status): "Couldn't talk to the Keychain (\(status))."
        case .missingAnthropicKey:
            "No Anthropic key in Keychain (service \(SecretStore.service), account anthropic) or ANTHROPIC_API_KEY."
        case let .anthropicHTTP(code, body): "Anthropic HTTP \(code): \(Trim.truncate(body, max: 200))"
        case let .decode(m): m
        }
    }
}
