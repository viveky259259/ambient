import Testing
@testable import AmbientCore

@Suite struct ShortcutTests {
    @Test func displayOrdersModifiersLikeMacOS() {
        #expect(Shortcut.optionEscape.display == "⌥⎋")
        #expect(Shortcut(keyCode: 1, modifiers: [.command, .shift, .option, .control], key: "S").display == "⌃⌥⇧⌘S")
        #expect(Shortcut(keyCode: 96, modifiers: [], key: "F5").display == "F5")
    }

    @Test func defaultAvoidsMacOSSpeakSelection() {
        #expect(Shortcut.default(systemSpeakSelectionOn: false) == .optionEscape)
        #expect(Shortcut.default(systemSpeakSelectionOn: true) == .controlOptionS)
    }

    @Test func allowedShortcuts() {
        #expect(Shortcut.optionEscape.problem == nil)
        #expect(Shortcut.controlOptionS.problem == nil)
        #expect(Shortcut(keyCode: 96, modifiers: [], key: "F5").problem == nil)
        #expect(Shortcut(keyCode: 1, modifiers: [.control, .command], key: "S").problem == nil)
    }

    @Test func plainOrCommandOnlyShortcutsWouldStealAppShortcuts() {
        #expect(Shortcut(keyCode: 1, modifiers: [], key: "S").problem == .needsControlOrOption)
        #expect(Shortcut(keyCode: 1, modifiers: [.command], key: "S").problem == .needsControlOrOption)
        #expect(Shortcut(keyCode: 1, modifiers: [.command, .shift], key: "S").problem == .needsControlOrOption)
        #expect(Shortcut(keyCode: 53, modifiers: [], key: "⎋").problem == .needsControlOrOption)
    }

    @Test func optionWithACharacterWouldStopYouTypingIt() {
        #expect(Shortcut(keyCode: 1, modifiers: [.option], key: "S").problem == .typesCharacter)
        #expect(Shortcut(keyCode: 49, modifiers: [.option, .shift], key: "Space").problem == .typesCharacter)
    }

    @Test func storedRoundTrip() {
        let s = Shortcut(keyCode: 1, modifiers: [.control, .option], key: "S")
        #expect(Shortcut(stored: s.stored) == s)
        #expect(Shortcut(stored: "nonsense") == nil)
    }

    @Test func keyNames() {
        #expect(Shortcut.keyName(keyCode: 53, characters: "\u{1b}") == "⎋")
        #expect(Shortcut.keyName(keyCode: 49, characters: " ") == "Space")
        #expect(Shortcut.keyName(keyCode: 96, characters: "") == "F5")
        #expect(Shortcut.keyName(keyCode: 1, characters: "s") == "S")
        #expect(Shortcut.keyName(keyCode: 126, characters: "") == "↑")
    }
}
