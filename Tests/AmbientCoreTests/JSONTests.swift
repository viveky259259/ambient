import Foundation
import Testing
@testable import AmbientCore

@Suite struct JSONTests {
    static let canonical = """
    {
      "zeta": 1,
      "alpha": {
        "nested": [
          true,
          false,
          null,
          -1.5e+10,
          "text with \\"quotes\\", \\\\ and \\n newline",
          "unicode é 🚀"
        ],
        "empty": {},
        "none": []
      },
      "m": "last"
    }
    """

    @Test func roundTripPreservesOrderAndBytes() throws {
        let value = try JSONValue.parse(Self.canonical)
        #expect(value.serialized(indent: "  ") == Self.canonical)
    }

    @Test func keysKeepTheirOrder() throws {
        let value = try JSONValue.parse(#"{"b":1,"a":2,"c":3}"#)
        #expect(value.objectKeys == ["b", "a", "c"])
    }

    @Test func numbersKeepTheirLexeme() throws {
        let value = try JSONValue.parse(#"[1.0, 100, 1e3]"#)
        #expect(value.serialized(indent: "  ") == "[\n  1.0,\n  100,\n  1e3\n]")
    }

    @Test func escapesDecodeAndReencode() throws {
        let value = try JSONValue.parse(#"["é🚀\t\/\u0001"]"#)
        #expect(value == .array([.string("é🚀\t/\u{01}")]))
        #expect(value.serialized(indent: "  ") == "[\n  \"é🚀\\t/\\u0001\"\n]")
    }

    @Test func subscriptsReadAndWrite() throws {
        var value = try JSONValue.parse(#"{"a":{"b":"c"}}"#)
        #expect(value["a"]?["b"] == .string("c"))
        value["a"]?["d"] = .bool(true)
        value["z"] = .null
        #expect(value.serialized(indent: "  ") == "{\n  \"a\": {\n    \"b\": \"c\",\n    \"d\": true\n  },\n  \"z\": null\n}")
        value["a"] = nil
        #expect(value.objectKeys == ["z"])
    }

    @Test(arguments: ["", "{", #"{"a" 1}"#, "[1,]", #"{"a":1} x"#, "tru", #""\x""#])
    func invalidInputThrows(text: String) {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(text) }
    }

    @Test func detectsIndentation() {
        #expect(JSONValue.detectIndent("{\n    \"a\": 1\n}") == "    ")
        #expect(JSONValue.detectIndent("{\n\t\"a\": 1\n}") == "\t")
        #expect(JSONValue.detectIndent("{}") == "  ")
    }
}
