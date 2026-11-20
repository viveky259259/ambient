import Foundation
import Testing
@testable import AmbientBase

private func parseError(_ text: String) -> JSONParseError? {
    do {
        _ = try JSONValue.parse(text)
        return nil
    } catch let error as JSONParseError {
        return error
    } catch {
        return nil
    }
}

/// Parses `depth` nested arrays on a thread with `stackSize` bytes of stack, waiting for it to finish.
private func qaParseNestedOnSmallStack(depth: Int, stackSize: Int) {
    let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    let done = DispatchSemaphore(value: 0)
    let thread = Thread { _ = try? JSONValue.parse(text); done.signal() }
    thread.stackSize = stackSize
    thread.start()
    done.wait()
}

private final class QABigStackBox<T>: @unchecked Sendable { var value: T? }

// MARK: - Parser

@Suite("JSON parser")
struct QAJSONParserTests {
    // Literals

    @Test(arguments: [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null),
                      (" \t\r\n true \n", .bool(true))])
    func literals(text: String, value: JSONValue) throws {
        #expect(try JSONValue.parse(text) == value)
    }

    @Test(arguments: ["t", "tru", "trUe", "True", "fals", "nul", "NULL", "nil", "truex", "nullnull", "true false"])
    func badLiterals(_ text: String) {
        #expect(parseError(text) != nil, "\(text)")
    }

    // Numbers

    @Test(arguments: ["0", "-0", "1", "-1", "123456789012345678901234567890", "0.5", "-0.5", "1.25e10", "1E10",
                      "1e+10", "1e-10", "-1.0E-0", "0e0", "3.141592653589793238462643383279"])
    func validNumbersKeepTheirSpelling(_ text: String) throws {
        #expect(try JSONValue.parse(text) == .number(text))
        #expect(try JSONValue.parse(text).serialized() == text)
    }

    @Test(arguments: ["-", "+1", ".5", "1.", "1.e5", "01", "-01", "00", "1e", "1e+", "1E-", "--1", "-a", "0x10",
                      "NaN", "Infinity", "-Infinity", "1.2.3", "1e5.5", "١"])
    func invalidNumbers(_ text: String) {
        #expect(parseError(text) != nil, "\(text)")
    }

    // Strings and escapes

    @Test(arguments: [
        (#""""#, ""),
        (#""\"""#, "\""), (#""\\""#, "\\"), (#""\/""#, "/"),
        (#""\b\f\n\r\t""#, "\u{08}\u{0C}\n\r\t"),
        (#""\u0041\u00e9\u00E9""#, "Aéé"),
        (#""\u0000""#, "\u{00}"),
        (#""\u20AC""#, "€"),
        (#""\uD83D\uDE80""#, "🚀"),                 // surrogate pair
        (#""\ud83d\ude80""#, "🚀"),                 // lowercase hex
        (#""\uDBFF\uDFFF""#, "\u{10FFFF}"),         // highest pair
        (#""\uD800\uDC00""#, "\u{10000}"),          // lowest pair
        ("\"é🚀 raw\"", "é🚀 raw"),                   // raw UTF-8 passes through
        ("\"\u{7F}\"", "\u{7F}"),                    // DEL is not a control character in JSON
    ])
    func stringEscapes(text: String, expected: String) throws {
        #expect(try JSONValue.parse(text) == .string(expected))
    }

    @Test(arguments: [
        (#""\uD800""#, "\u{FFFD}"),               // lone high surrogate at end
        (#""\uDC00""#, "\u{FFFD}"),               // lone low surrogate
        (#""\uDFFF x""#, "\u{FFFD} x"),
        (#""\uD800x""#, "\u{FFFD}x"),            // high surrogate followed by plain text
        (#""\uD800\n""#, "\u{FFFD}\n"),          // high surrogate followed by another escape
        (#""\uD800\uD800\uDC00""#, "\u{FFFD}"),
    ])
    func loneSurrogatesBecomeReplacementCharacters(text: String, expected: String) throws {
        // A bad pair still yields one replacement character; the cases with a valid follow-up escape are
        // covered separately below.
        let value = try JSONValue.parse(text)
        #expect(value.stringValue?.hasPrefix("\u{FFFD}") == true, "\(text)")
        if !text.contains(#"\uD800\uD800"#) { #expect(value == .string(expected), "\(text)") }
    }

    @Test func highSurrogateFollowedByANonSurrogateEscapeKeepsTheSecondCharacter() throws {
        // A lone high surrogate followed by an ordinary \u escape: the ordinary character should survive.
        withKnownIssue("BUG: JSONParser swallows the \\u escape after a lone high surrogate (\"\\uD800\\u0041\" → \"\u{FFFD}\" not \"\u{FFFD}A\")") {
            let value = try JSONValue.parse(#""\uD800\u0041""#)
            #expect(value == .string("\u{FFFD}A"))
        }
    }

    @Test(arguments: [
        #""abc"#, #"""#, #""\"#, #""\q""#, #""\x41""#, #""\u12""#, #""\u12G4""#, #""\uZZZZ""#, #""\U0041""#, #""\"abc"#,
        "\"a\u{01}b\"", "\"tab\there\"", "\"line\nbreak\"", "\"\u{1F}\"", "'single'", #""\uD800\u""#,
    ])
    func invalidStrings(_ text: String) {
        #expect(parseError(text) != nil, "\(text.debugDescription)")
    }

    @Test func invalidUTF8IsRepairedNotRejected() throws {
        let data = Data([0x22, 0xFF, 0xFE, 0x22])  // "\xFF\xFE"
        let value = try JSONValue.parse(data)
        #expect(value.stringValue?.unicodeScalars.allSatisfy { $0 == "\u{FFFD}" } == true)
    }

    // Containers

    @Test func nestedContainers() throws {
        let v = try JSONValue.parse(#" { "a" : [ 1 , { "b" : null } , [ ] , { } ] , "c" : "d" } "#)
        #expect(v == .object([
            .init("a", .array([.number("1"), .object([.init("b", .null)]), .array([]), .object([])])),
            .init("c", .string("d")),
        ]))
    }

    @Test func duplicateKeysAreKeptInOrder() throws {
        let v = try JSONValue.parse(#"{"a":1,"a":2}"#)
        #expect(v.objectKeys == ["a", "a"])
        #expect(v["a"] == .number("1"))
    }

    @Test func emptyKey() throws {
        #expect(try JSONValue.parse(#"{"":1}"#)[""] == .number("1"))
    }

    @Test(arguments: ["[", "]", "[1", "[1,", "[1 2]", "[,1]", "[1,,2]", "{", "}", #"{"a""#, #"{"a":"#, #"{"a":1"#,
                      #"{"a":1,}"#, #"{a:1}"#, #"{1:1}"#, #"{"a";1}"#, #"{"a":1 "b":2}"#, #"{"a":1]"#, "[1}",
                      "{,}", "[] []", "{}}", "\u{0C}1", "1\u{0C}", "\u{A0}1"])
    func invalidContainersAndWhitespace(_ text: String) {
        #expect(parseError(text) != nil, "\(text.debugDescription)")
    }

    @Test(arguments: ["", " ", "\n\t\r "])
    func emptyDocumentIsAnError(_ text: String) {
        let e = parseError(text)
        #expect(e?.message == "Unexpected end of input")
        #expect(e?.offset == text.utf8.count)
    }

    // BOM

    @Test func byteOrderMarkIsTolerated() throws {
        #expect(try JSONValue.parse("\u{FEFF}{\"a\":1}") == .object([.init("a", .number("1"))]))
        #expect(try JSONValue.parse(Data([0xEF, 0xBB, 0xBF] + Array("[true]".utf8))) == .array([.bool(true)]))
    }

    @Test func onlyOneLeadingBOMIsTolerated() {
        #expect(parseError("\u{FEFF}\u{FEFF}1") != nil)
        #expect(parseError("1\u{FEFF}") != nil)
        #expect(parseError("\u{FEFF}") != nil)
    }

    @Test func errorOffsetsAfterABOMCountTheInputBytes() {
        // "\u{FEFF}x" is 3 BOM bytes then the bad byte at offset 3 of the input.
        withKnownIssue("BUG: JSONParser reports offsets relative to the BOM-stripped bytes, 3 short of the input's byte offset") {
            #expect(parseError("\u{FEFF}x")?.offset == 3)
        }
    }

    // Depth

    /// Runs `body` on a thread with an 8 MiB stack (a main thread's), so deep-nesting tests measure the parser's
    /// limit rather than the test runner's small worker stacks.
    private func onBigStack<T: Sendable>(_ body: @escaping @Sendable () -> T) -> T {
        let box = QABigStackBox<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread { box.value = body(); done.signal() }
        thread.stackSize = 8 << 20
        thread.start()
        done.wait()
        return box.value!
    }

    private static func nestedArrays(_ depth: Int) -> String {
        String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    }

    @Test func nestingUpTo512LevelsParses() {
        let depth = onBigStack { () -> Int in
            guard var v = try? JSONValue.parse(Self.nestedArrays(512)) else { return -1 }
            var depth = 0
            while case let .array(items) = v, let first = items.first { v = first; depth += 1 }
            return depth
        }
        #expect(depth == 511)
    }

    @Test func nestingBeyond512LevelsIsRejectedWithItsOffset() {
        let e = onBigStack { parseError(Self.nestedArrays(513)) }
        #expect(e?.message == "Nesting too deep")
        #expect(e?.offset == 512)
    }

    @Test func deepObjectsAreLimitedToo() {
        let text = String(repeating: #"{"a":"#, count: 600) + "1" + String(repeating: "}", count: 600)
        #expect(onBigStack { parseError(text) }?.message == "Nesting too deep")
    }

    @Test func hugeNestingIsRejected() {
        #expect(onBigStack { parseError(String(repeating: "[", count: 100_000)) }?.message == "Nesting too deep")
    }

    /// The 512-level limit isn't sized to a secondary thread's 512 KiB stack in debug builds: ~400 levels fit,
    /// 448 don't. Optimized builds parse 511 levels in 128 KiB, so this is debug/test-only. Run in a child process.
    @Test func nestingWithinTheLimitFitsASecondaryThreadStack() async {
        await withKnownIssue("BUG (debug builds): JSONValue.parse overflows a 512 KiB thread stack below its own 512-level limit", isIntermittent: true) {
            await #expect(processExitsWith: .success) {
                qaParseNestedOnSmallStack(depth: 511, stackSize: 512 * 1024)
            }
        }
    }

    // Error messages and offsets

    @Test(arguments: [
        ("x", "Unexpected character", 0),
        ("tru", "Invalid literal", 0),
        ("[1,]", "Unexpected character", 3),
        (#"{"a" 1}"#, "Expected ':'", 5),
        (#"{"a":1 "b":2}"#, "Expected ',' or '}'", 7),
        ("[1 2]", "Expected ',' or ']'", 3),
        ("{1:1}", "Expected a key", 1),
        (#"{"a":1"#, "Unterminated object", 6),
        ("[1", "Unterminated array", 2),
        (#""abc"#, "Unterminated string", 4),
        (#""\"#, "Unterminated escape", 2),
        (#""\q""#, "Invalid escape", 3),
        (#""\u12G4""#, "Invalid \u{5C}u escape", 5),
        (#""\u12"#, "Invalid \u{5C}u escape", 3),
        ("\"a\u{01}\"", "Control character in string", 2),
        ("01", "Unexpected content after the document", 1),
        ("-", "Invalid number", 1),
        ("1.", "Invalid number", 2),
        ("1e", "Invalid number", 2),
        ("-x", "Invalid number", 1),
    ])
    func errorMessageAndOffset(text: String, message: String, offset: Int) {
        let e = parseError(text)
        #expect(e?.message == message, "\(text)")
        #expect(e?.offset == offset, "\(text)")
    }

    @Test func errorDescriptionNamesTheByte() {
        let e = JSONParseError(message: "Boom", offset: 7)
        #expect(e.description == "Boom at byte 7")
        #expect(e == JSONParseError(message: "Boom", offset: 7))
        #expect(e != JSONParseError(message: "Boom", offset: 8))
    }

    @Test func offsetsCountUTF8Bytes() {
        // "é" is two bytes, so the stray "x" after the string is at byte 4.
        #expect(parseError("\"é\"x")?.offset == 4)
    }

    @Test func stringAndDataEntryPointsAgree() throws {
        let text = #"{"k":[1,"two",{"three":null}],"é":"🚀"}"#
        #expect(try JSONValue.parse(text) == JSONValue.parse(Data(text.utf8)))
    }
}

// MARK: - Writer

@Suite("JSON writer")
struct QAJSONWriterTests {
    @Test func scalars() {
        #expect(JSONValue.null.serialized() == "null")
        #expect(JSONValue.bool(true).serialized() == "true")
        #expect(JSONValue.bool(false).serialized() == "false")
        #expect(JSONValue.number("-1.5e3").serialized() == "-1.5e3")
        #expect(JSONValue.string("hi").serialized() == "\"hi\"")
    }

    @Test func emptyContainersStayOnOneLine() {
        #expect(JSONValue.array([]).serialized() == "[]")
        #expect(JSONValue.object([]).serialized() == "{}")
        #expect(JSONValue.array([.array([]), .object([])]).serialized() == "[\n  [],\n  {}\n]")
    }

    @Test func customIndent() {
        let v = JSONValue.object([.init("a", .array([.number("1")]))])
        #expect(v.serialized(indent: "\t") == "{\n\t\"a\": [\n\t\t1\n\t]\n}")
        #expect(v.serialized(indent: "    ") == "{\n    \"a\": [\n        1\n    ]\n}")
        #expect(v.serialized(indent: "") == "{\n\"a\": [\n1\n]\n}")
    }

    @Test func defaultIndentIsTwoSpaces() {
        let v = JSONValue.array([.null])
        #expect(v.serialized() == v.serialized(indent: "  "))
    }

    @Test(arguments: [
        ("\"", #""\"""#), ("\\", #""\\""#), ("\u{08}", #""\b""#), ("\u{0C}", #""\f""#), ("\n", #""\n""#),
        ("\r", #""\r""#), ("\t", #""\t""#), ("\u{00}", #""\u0000""#), ("\u{1F}", #""\u001f""#),
        ("\u{0B}", #""\u000b""#), ("/", #""/""#), ("\u{7F}", "\"\u{7F}\""), ("é🚀", "\"é🚀\""),
        ("\u{2028}", "\"\u{2028}\""),
    ])
    func stringEscaping(raw: String, encoded: String) {
        #expect(JSONValue.string(raw).serialized() == encoded)
    }

    @Test func keysAreEscapedToo() {
        let v = JSONValue.object([.init("a\"b\n", .null)])
        #expect(v.serialized() == "{\n  \"a\\\"b\\n\": null\n}")
    }

    @Test func numberLexemeIsWrittenVerbatim() {
        // The writer trusts `.number`; it does not validate it.
        #expect(JSONValue.number("not-a-number").serialized() == "not-a-number")
    }

    static let roundTripDocuments: [String] = [
        "null", "true", "0", "-1.5E+3", #""""#, "[]", "{}",
        #"{"a":[1,2,{"b":[true,false,null]}],"c":{}}"#,
        #"["\u0000\u001f\"\\\/\b\f\n\r\t", "\uD83D\uDE80", "é", "\u2028"]"#,
        #"{"z":1,"a":2,"m":{"y":[],"b":{"":""}}}"#,
    ]

    @Test(arguments: roundTripDocuments)
    func parseSerializeParseIsStable(text: String) throws {
        let v = try JSONValue.parse(text)
        for indent in ["  ", "\t", "    "] {
            let out = v.serialized(indent: indent)
            #expect(try JSONValue.parse(out) == v, "\(indent.debugDescription)")
            // Serializing again is a fixed point.
            #expect(try JSONValue.parse(out).serialized(indent: indent) == out)
        }
    }

    @Test(arguments: roundTripDocuments)
    func outputIsValidForFoundation(text: String) throws {
        let out = try JSONValue.parse(text).serialized()
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: Data(out.utf8), options: [.fragmentsAllowed])
        }
    }

    @Test func everyControlCharacterRoundTrips() throws {
        let all = String(String.UnicodeScalarView((0..<0x20).compactMap(Unicode.Scalar.init)))
        let v = JSONValue.string(all)
        #expect(try JSONValue.parse(v.serialized()) == v)
    }

    @Test func matchesJSONStringifyShape() throws {
        // `JSON.stringify(v, null, 2)` shape, which JSONSerialization's pretty printer also uses (modulo " : ").
        let text = "{\n  \"a\": [\n    1,\n    \"x\"\n  ],\n  \"b\": {}\n}"
        #expect(try JSONValue.parse(text).serialized() == text)
    }
}

// MARK: - JSONValue accessors

@Suite("JSONValue accessors")
struct QAJSONValueTests {
    @Test func stringValueIsNilForOtherCases() {
        let all: [JSONValue] = [.null, .bool(true), .number("1"), .string("s"), .array([.string("s")]),
                                .object([.init("k", .string("s"))])]
        for v in all {
            if case .string = v { #expect(v.stringValue == "s") } else { #expect(v.stringValue == nil) }
        }
        #expect(JSONValue.string("").stringValue == "")
    }

    @Test func keySubscriptGetOnNonObjectIsNil() {
        #expect(JSONValue.array([])["a"] == nil)
        #expect(JSONValue.string("a")["a"] == nil)
        #expect(JSONValue.object([])["missing"] == nil)
    }

    @Test func keySubscriptSetOnNonObjectIsANoOp() {
        var v = JSONValue.array([.null])
        v["a"] = .bool(true)
        #expect(v == .array([.null]))
        var s = JSONValue.null
        s["a"] = .null
        #expect(s == .null)
    }

    @Test func keySubscriptReplacesInPlaceAndAppendsNewKeys() {
        var v = JSONValue.object([.init("a", .number("1")), .init("b", .number("2"))])
        v["a"] = .number("9")
        v["c"] = .number("3")
        #expect(v.objectKeys == ["a", "b", "c"])
        #expect(v["a"] == .number("9"))
    }

    @Test func keySubscriptNilRemovesAndMissingNilIsANoOp() {
        var v = JSONValue.object([.init("a", .null), .init("b", .null)])
        v["a"] = nil
        #expect(v.objectKeys == ["b"])
        v["zzz"] = nil
        #expect(v.objectKeys == ["b"])
    }

    @Test func settingNullIsNotRemoval() {
        var v = JSONValue.object([.init("a", .number("1"))])
        v["a"] = .null
        #expect(v.objectKeys == ["a"])
        #expect(v["a"] == .null)
    }

    @Test func duplicateKeysTouchOnlyTheFirst() {
        var v = JSONValue.object([.init("a", .number("1")), .init("a", .number("2"))])
        v["a"] = .number("9")
        #expect(v == .object([.init("a", .number("9")), .init("a", .number("2"))]))
        v["a"] = nil
        #expect(v == .object([.init("a", .number("2"))]))
    }

    @Test func indexSubscript() {
        var v = JSONValue.array([.number("0"), .number("1"), .number("2")])
        #expect(v[0] == .number("0"))
        #expect(v[2] == .number("2"))
        #expect(v[3] == nil)
        #expect(v[-1] == nil)
        v[1] = .string("one")
        #expect(v[1] == .string("one"))
        v[0] = nil
        #expect(v == .array([.string("one"), .number("2")]))
        v[5] = .null     // out of range: ignored, not appended
        v[-1] = nil
        #expect(v.arrayCount == 2)
    }

    @Test func indexSubscriptOnNonArray() {
        var v = JSONValue.object([.init("a", .null)])
        #expect(v[0] == nil)
        v[0] = .null
        #expect(v == .object([.init("a", .null)]))
    }

    @Test func nestedMutationThroughOptionalChaining() {
        var v = JSONValue.object([.init("list", .array([.object([])]))])
        v["list"]?[0]?["k"] = .bool(true)
        #expect(v["list"]?[0]?["k"] == .bool(true))
        v["missing"]?["k"] = .null   // nothing to chain into: no change
        #expect(v.objectKeys == ["list"])
    }

    @Test func memberInitAndMutation() {
        var m = JSONValue.Member("k", .null)
        m.key = "j"
        m.value = .bool(false)
        #expect(m == JSONValue.Member("j", .bool(false)))
    }

    @Test func numbersCompareBySpelling() {
        #expect(JSONValue.number("1") != JSONValue.number("1.0"))
    }

    // detectIndent

    @Test(arguments: [
        ("{\n  \"a\": 1\n}", "  "), ("{\n    \"a\": 1\n}", "    "), ("{\n\t\"a\": 1\n}", "\t"),
        ("{\n\t  \"a\": 1\n}", "\t  "), ("[]", "  "), ("", "  "), ("{\"a\":1}", "  "),
        ("{\n\n\n   \"a\": 1\n}", "   "),                // blank lines are skipped
        ("   {\n\"a\": 1\n}", "  "),                     // the first line's indentation is ignored
        ("{\n\"a\": [\n      1\n]\n}", "      "),        // first indented line wins
        ("{\r\n  \"a\": 1\r\n}", "  "),
    ])
    func detectIndent(text: String, expected: String) {
        #expect(JSONValue.detectIndent(text) == expected)
    }

    @Test func detectIndentFeedsTheWriter() throws {
        let text = "{\n    \"a\": [\n        1\n    ]\n}"
        #expect(try JSONValue.parse(text).serialized(indent: JSONValue.detectIndent(text)) == text)
    }
}
