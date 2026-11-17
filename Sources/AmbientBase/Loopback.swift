import Foundation

extension URL {
    /// An http(s) URL on this Mac: `127.0.0.1`, `localhost` or `::1`. What may receive text that must not leave it.
    public var isLoopback: Bool {
        let scheme = scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return false }
        let host = (host ?? "").lowercased()
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
