import Foundation

/// The JSON object an agent hands its hook on stdin, with forgiving typed accessors.
public struct HookPayload: @unchecked Sendable {
    public let raw: [String: Any]

    public init(_ raw: [String: Any]) {
        self.raw = raw
    }

    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]),
              let dict = object as? [String: Any] else { return nil }
        self.raw = dict
    }

    public func string(_ key: String) -> String? {
        switch raw[key] {
        case let s as String: s
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): n.stringValue
        default: nil
        }
    }

    public func object(_ key: String) -> HookPayload? {
        (raw[key] as? [String: Any]).map(HookPayload.init)
    }

    /// True when the key holds a value other than null.
    public func has(_ key: String) -> Bool {
        guard let v = raw[key] else { return false }
        return !(v is NSNull)
    }

    /// The first non-blank string among `keys`.
    public func firstString(_ keys: [String]) -> String? {
        for key in keys {
            if let s = string(key), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        }
        return nil
    }
}
