import AmbientCore
import Foundation
import Security

/// API keys for online voices, in the login Keychain. Never in files or preferences.
///
/// The Keychain can stop to ask the user, so the UI goes through `load` and `save`, which run on one serial queue
/// off the main thread; ordering on that queue means a read after a save sees the saved key.
enum KeychainStore {
    static let service = "com.viveky259259.Ambient.voice"
    static let queue = DispatchQueue(label: "com.viveky259259.Ambient.keychain", qos: .userInitiated)

    /// The stored key, or "" when there is none or it can't be read, delivered on the main thread.
    static func load(for provider: OnlineProvider, _ done: @escaping (String) -> Void) {
        queue.async {
            let key = self.key(for: provider) ?? ""
            DispatchQueue.main.async { done(key) }
        }
    }

    /// Saves a key the user typed; an emptied field forgets it.
    static func save(_ key: String, for provider: OnlineProvider) {
        queue.async {
            if key.isEmpty { deleteKey(for: provider) } else { try? setKey(key, for: provider) }
        }
    }

    private static func query(_ provider: OnlineProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    static func key(for provider: OnlineProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setKey(_ key: String, for provider: OnlineProvider) throws {
        deleteKey(for: provider)
        var q = query(provider)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SpeechFailure(message: "Couldn't save the key to the Keychain (\(status)).")
        }
    }

    static func deleteKey(for provider: OnlineProvider) {
        SecItemDelete(query(provider) as CFDictionary)
    }
}
