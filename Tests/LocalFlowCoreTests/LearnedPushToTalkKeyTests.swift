import Testing
@testable import LocalFlowCore

@Test func createsLearnedNormalKeyFromKeyCodeAndDisplayName() {
    let key = PushToTalkKey.learned(
        keyCode: 49,
        displayName: "Leertaste",
        isModifier: false
    )

    #expect(key.title == "Leertaste")
    #expect(key.keyCode == 49)
    #expect(!key.isModifier)
    #expect(key.rawValue == "learned:key:49:Leertaste")
}

@Test func restoresLearnedNormalKeyFromSavedValue() {
    let key = PushToTalkKey(savedValue: "learned:key:49:Leertaste")

    #expect(key.title == "Leertaste")
    #expect(key.keyCode == 49)
    #expect(!key.isModifier)
}

@Test func restoresLearnedModifierKeyFromSavedValue() {
    let key = PushToTalkKey(savedValue: "learned:modifier:56:Shift")

    #expect(key.title == "Shift")
    #expect(key.keyCode == 56)
    #expect(key.isModifier)
}

@Test func functionKeyModifierIsSupported() {
    let key = PushToTalkKey.learned(
        keyCode: 63,
        displayName: "Fn/Globe",
        isModifier: true
    )

    #expect(key.modifierKind == .function)
    #expect(PushToTalkKey(savedValue: key.rawValue).modifierKind == .function)
}

@Test func createsAndRestoresLearnedMediaKey() {
    let key = PushToTalkKey.learnedMedia(keyCode: 16, displayName: "Play/Pause")

    #expect(key.title == "Play/Pause")
    #expect(key.keyCode == 0)
    #expect(key.mediaKeyCode == 16)
    #expect(key.rawValue == "learned:media:16:Play/Pause")
    #expect(PushToTalkKey(savedValue: key.rawValue) == key)
}
