import AmbientCore

/// Test-only readers for JSONValue, so assertions can look at a parsed config without the product carrying them.
extension JSONValue {
    var objectKeys: [String]? {
        guard case let .object(members) = self else { return nil }
        return members.map(\.key)
    }

    var arrayCount: Int? {
        guard case let .array(items) = self else { return nil }
        return items.count
    }
}

/// Whether the board would refuse this config's MCP URL: missing, or not loopback http(s).
func refusesNonLoopback(_ config: TaskLLMConfig) -> Bool {
    guard let url = config.mcpEndpoint else { return true }
    return !url.isLoopback
}
