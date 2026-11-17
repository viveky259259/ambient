import Foundation

public struct JSONParseError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let offset: Int

    public var description: String { "\(message) at byte \(offset)" }
}

extension JSONValue {
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(text.utf8))
        return try parser.parseDocument()
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(data))
        return try parser.parseDocument()
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var i = 0

    init(bytes: [UInt8]) {
        // Tolerate a UTF-8 byte order mark.
        self.bytes = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
    }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard i == bytes.count else { throw fail("Unexpected content after the document") }
        return value
    }

    private func fail(_ message: String) -> JSONParseError {
        JSONParseError(message: message, offset: i)
    }

    private mutating func skipWhitespace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    private mutating func expect(_ literal: String, _ value: JSONValue) throws -> JSONValue {
        let lit = Array(literal.utf8)
        guard bytes.count - i >= lit.count, Array(bytes[i..<i + lit.count]) == lit else {
            throw fail("Invalid literal")
        }
        i += lit.count
        return value
    }

    private mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth < 512 else { throw fail("Nesting too deep") }
        guard i < bytes.count else { throw fail("Unexpected end of input") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try parseObject(depth: depth)
        case UInt8(ascii: "["): return try parseArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): return try expect("true", .bool(true))
        case UInt8(ascii: "f"): return try expect("false", .bool(false))
        case UInt8(ascii: "n"): return try expect("null", .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw fail("Unexpected character")
        }
    }

    private mutating func parseObject(depth: Int) throws -> JSONValue {
        i += 1
        var members: [JSONValue.Member] = []
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
        while true {
            skipWhitespace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("Expected a key") }
            let key = try parseString()
            skipWhitespace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("Expected ':'") }
            i += 1
            skipWhitespace()
            members.append(JSONValue.Member(key, try parseValue(depth: depth + 1)))
            skipWhitespace()
            guard i < bytes.count else { throw fail("Unterminated object") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
            throw fail("Expected ',' or '}'")
        }
    }

    private mutating func parseArray(depth: Int) throws -> JSONValue {
        i += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            skipWhitespace()
            items.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            guard i < bytes.count else { throw fail("Unterminated array") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw fail("Expected ',' or ']'")
        }
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = i
        func digits() -> Int {
            let s = i
            while i < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) { i += 1 }
            return i - s
        }
        if bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard i < bytes.count else { throw fail("Invalid number") }
        if bytes[i] == UInt8(ascii: "0") { i += 1 } else if digits() == 0 { throw fail("Invalid number") }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            i += 1
            guard digits() > 0 else { throw fail("Invalid number") }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard digits() > 0 else { throw fail("Invalid number") }
        }
        return .number(String(decoding: bytes[start..<i], as: UTF8.self))
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard bytes.count - i >= 4 else { throw fail("Invalid \\u escape") }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let c = bytes[i]
            let d: UInt32
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): d = UInt32(c - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): d = UInt32(c - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): d = UInt32(c - UInt8(ascii: "A") + 10)
            default: throw fail("Invalid \\u escape")
            }
            v = v * 16 + d
            i += 1
        }
        return v
    }

    private mutating func parseString() throws -> String {
        i += 1
        var out: [UInt8] = []
        while true {
            guard i < bytes.count else { throw fail("Unterminated string") }
            let c = bytes[i]
            if c == UInt8(ascii: "\"") { i += 1; return String(decoding: out, as: UTF8.self) }
            guard c >= 0x20 else { throw fail("Control character in string") }
            if c != UInt8(ascii: "\\") { out.append(c); i += 1; continue }

            i += 1
            guard i < bytes.count else { throw fail("Unterminated escape") }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""): out.append(0x22)
            case UInt8(ascii: "\\"): out.append(0x5C)
            case UInt8(ascii: "/"): out.append(0x2F)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "u"):
                var scalar = try parseHex4()
                if (0xD800...0xDBFF).contains(scalar) {
                    if bytes.count - i >= 6, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                        i += 2
                        let low = try parseHex4()
                        scalar = (0xDC00...0xDFFF).contains(low)
                            ? 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                            : 0xFFFD
                    } else {
                        scalar = 0xFFFD
                    }
                } else if (0xDC00...0xDFFF).contains(scalar) {
                    scalar = 0xFFFD
                }
                out.append(contentsOf: Array(String(Character(Unicode.Scalar(scalar)!)).utf8))
            default:
                throw fail("Invalid escape")
            }
        }
    }
}
