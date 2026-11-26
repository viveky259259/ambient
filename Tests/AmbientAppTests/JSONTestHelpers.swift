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
