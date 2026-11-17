import Foundation

/// A JSON document that keeps object key order and number spelling, so Ambient can edit
/// other tools' config files without reshuffling them.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// The number exactly as written.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([Member])

    public struct Member: Equatable, Sendable {
        public var key: String
        public var value: JSONValue

        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    public var objectKeys: [String]? {
        guard case let .object(members) = self else { return nil }
        return members.map(\.key)
    }

    public var arrayCount: Int? {
        guard case let .array(items) = self else { return nil }
        return items.count
    }

    public var stringValue: String? {
        guard case let .string(s) = self else { return nil }
        return s
    }

    /// Object member access. Setting nil removes the key; setting a new key appends it.
    public subscript(key: String) -> JSONValue? {
        get {
            guard case let .object(members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case var .object(members) = self else { return }
            if let i = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[i].value = newValue } else { members.remove(at: i) }
            } else if let newValue {
                members.append(Member(key, newValue))
            }
            self = .object(members)
        }
    }

    /// Array element access. Setting nil removes the element.
    public subscript(index: Int) -> JSONValue? {
        get {
            guard case let .array(items) = self, items.indices.contains(index) else { return nil }
            return items[index]
        }
        set {
            guard case var .array(items) = self, items.indices.contains(index) else { return }
            if let newValue { items[index] = newValue } else { items.remove(at: index) }
            self = .array(items)
        }
    }

    /// The indentation unit used by a pretty-printed document; two spaces when unknown.
    public static func detectIndent(_ text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
            let lead = line.prefix { $0 == " " || $0 == "\t" }
            if !lead.isEmpty { return String(lead) }
        }
        return "  "
    }
}
