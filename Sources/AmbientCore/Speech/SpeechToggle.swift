/// What a press of the read-aloud shortcut (or Services › Speak with Ambient) does.
public enum SpeechToggle {
    public enum Action: Equatable, Sendable {
        /// Stop what's being read.
        case stop
        /// Tell the user to select something.
        case nothingSelected
        /// No voice chosen yet: ask first.
        case choose
        /// Read `spoken`, replacing anything playing.
        case speak
    }

    /// `spoken` is the selection after `SpeechText.spoken`; `last` is what the current job is reading. Pressing again
    /// on the same text, or with nothing selected, stops; new text replaces what's playing.
    public static func decide(active: Bool, spoken: String, last: String?, hasEngine: Bool) -> Action {
        if active, spoken.isEmpty || spoken == last { return .stop }
        if spoken.isEmpty { return .nothingSelected }
        return hasEngine ? .speak : .choose
    }
}
