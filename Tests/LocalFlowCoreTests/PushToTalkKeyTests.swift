import Testing
@testable import LocalFlowCore

@Test func offersSupportedPushToTalkKeys() {
    #expect(PushToTalkKey.allCases.map(\.title) == [
        "Rechte Wahltaste (⌥)",
        "Linke Wahltaste (⌥)",
        "Rechte Befehlstaste (⌘)",
        "Linke Befehlstaste (⌘)",
        "F8",
        "F9"
    ])
}

@Test func defaultsToRightOptionKey() {
    #expect(PushToTalkKey.defaultKey == .rightOption)
    #expect(PushToTalkKey.rightOption.keyCode == 61)
    #expect(PushToTalkKey.rightOption.isModifier)
}

@Test func functionKeyIsNotAModifier() {
    #expect(PushToTalkKey.f8.keyCode == 100)
    #expect(!PushToTalkKey.f8.isModifier)
}

@Test func restoresSavedKeyOrFallsBackToDefault() {
    #expect(PushToTalkKey(savedValue: "f9") == .f9)
    #expect(PushToTalkKey(savedValue: "unknown") == .defaultKey)
    #expect(PushToTalkKey(savedValue: nil) == .defaultKey)
}
