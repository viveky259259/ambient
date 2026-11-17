import Foundation

// Public names AmbientCore had before AmbientBase and AmbientContracts were split out of it, kept so code that imports
// AmbientCore builds unchanged. Phase 4 of docs/superpowers/specs/2026-11-13-modular-packages-design.md removes them.

extension AlertPolicy {
    @available(*, deprecated, message: "Use Mood.wantsAttention")
    public static let attentionMoods: Set<Mood> = Set(Mood.allCases.filter(\.wantsAttention))
}

extension TaskLLMConfig {
    @available(*, deprecated, message: "Use URL.isLoopback")
    public static func isLoopback(_ url: URL) -> Bool { url.isLoopback }
}

extension SessionStore {
    @available(*, deprecated, renamed: "ProcessProbe.isAlive")
    public static func processExists(_ pid: Int32) -> Bool { ProcessProbe.isAlive(pid) }
}

extension RemoteEventDecoder {
    @available(*, deprecated, renamed: "Trim.plainText")
    public static func plainText(_ s: String, max: Int) -> String? { Trim.plainText(s, max: max) }
}

extension RemoteEventDecoder.Caps {
    @available(*, deprecated, renamed: "Trim.maxScalarsPerCharacter")
    public static var scalarsPerCharacter: Int { Trim.maxScalarsPerCharacter }
}
