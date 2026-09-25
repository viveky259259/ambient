import Foundation

extension JSONValue {
    /// Pretty-prints the way `JSON.stringify(value, null, indent)` does.
    public func serialized(indent: String = "  ") -> String {
        var out = ""
        write(to: &out, level: 0, indent: indent)
        return out
    }

    private func write(to out: inout String, level: Int, indent: String) {
        switch self {
        case .null: out += "null"
        case let .bool(b): out += b ? "true" : "false"
        case let .number(n): out += n
        case let .string(s): Self.quote(s, into: &out)
        case let .array(items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (n, item) in items.enumerated() {
                out += String(repeating: indent, count: level + 1)
                item.write(to: &out, level: level + 1, indent: indent)
                out += n == items.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: indent, count: level) + "]"
        case let .object(members):
            guard !members.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (n, member) in members.enumerated() {
                out += String(repeating: indent, count: level + 1)
                Self.quote(member.key, into: &out)
                out += ": "
                member.value.write(to: &out, level: level + 1, indent: indent)
                out += n == members.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: indent, count: level) + "}"
        }
    }

    private static func quote(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
