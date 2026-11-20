import Foundation
@testable import AmbientCore

/// A fake local-agent MCP gateway behind URLProtocol. Each test registers its own port, so tests running in
/// parallel never see each other's requests.
final class QAStubGateway: @unchecked Sendable {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        var error: Error?
    }

    /// One received request: method, params and the headers it carried.
    struct Call {
        let method: String?
        let params: [String: Any]
        let headers: [String: String]
    }

    private static let lock = NSLock()
    /// Weak, so a test's gateway goes when the test does, and no deinit ever needs the lock.
    private final class Weak { weak var gateway: QAStubGateway?; init(_ g: QAStubGateway) { gateway = g } }
    nonisolated(unsafe) private static var gateways: [Int: Weak] = [:]
    nonisolated(unsafe) private static var nextPort = 41_000

    let port: Int
    var url: URL { URL(string: "http://127.0.0.1:\(port)/mcp")! }
    private let lock = NSLock()
    private var _calls: [Call] = []
    /// Answers a JSON-RPC message.
    var handler: (_ method: String?, _ params: [String: Any], _ id: Any?) -> Reply

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    /// `port` 443 stands in for a default https URL such as Anthropic's, which names no port.
    init(port fixed: Int? = nil, handler: @escaping (_ method: String?, _ params: [String: Any], _ id: Any?) -> Reply) {
        self.handler = handler
        Self.lock.lock()
        if let fixed {
            port = fixed
        } else {
            port = Self.nextPort
            Self.nextPort += 1
        }
        Self.gateways[port] = Weak(self)
        Self.lock.unlock()
    }

    static func gateway(for url: URL?) -> QAStubGateway? {
        guard let url, let port = url.port ?? (url.scheme == "https" ? 443 : nil) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return gateways[port]?.gateway
    }

    /// A URLSession that sends everything to the stubs.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QAStubProtocol.self]
        return URLSession(configuration: config)
    }

    func mcp() -> LocalAgentMCP {
        LocalAgentMCP(config: .init(url: url, requestTimeout: 5), session: Self.session())
    }

    func record(_ call: Call) { lock.lock(); _calls.append(call); lock.unlock() }

    // MARK: - Reply builders

    static func sse(_ object: [String: Any], headers: [String: String] = [:]) -> Reply {
        let json = try! JSONSerialization.data(withJSONObject: object)
        let body = Data("event: message\ndata: ".utf8) + json + Data("\n\n".utf8)
        return Reply(status: 200, headers: headers.merging(["Content-Type": "text/event-stream"]) { a, _ in a }, body: body)
    }

    static func result(_ id: Any?, _ result: Any, headers: [String: String] = [:]) -> Reply {
        sse(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result], headers: headers)
    }

    /// A tools/call result whose single text content is `object` as JSON.
    static func toolJSON(_ id: Any?, _ object: Any) -> Reply {
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return result(id, ["content": [["type": "text", "text": text]]])
    }

    /// The usual gateway: initialize hands out a session id, notifications are accepted, tools go to `tools`.
    static func standard(sessionID: String = "sess-1",
                         tools: @escaping (_ name: String, _ arguments: [String: Any], _ id: Any?) -> Reply) -> QAStubGateway {
        QAStubGateway { method, params, id in
            switch method {
            case "initialize": return result(id, ["protocolVersion": "2025-03-26"], headers: ["Mcp-Session-Id": sessionID])
            case "notifications/initialized": return Reply(status: 202)
            case "tools/call":
                return tools(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:], id)
            default: return Reply(status: 404)
            }
        }
    }
}

final class QAStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let gateway = QAStubGateway.gateway(for: request.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let body = Self.body(of: request)
        let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let method = message["method"] as? String
        let params = message["params"] as? [String: Any] ?? [:]
        gateway.record(.init(method: method, params: params, headers: request.allHTTPHeaderFields ?? [:]))
        let reply = gateway.handler(method, params, message["id"])
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
