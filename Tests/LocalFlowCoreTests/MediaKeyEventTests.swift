import Testing
@testable import LocalFlowCore

@Test func decodesPlayKeyDownAndUpEvents() {
    #expect(MediaKeyEvent(data1: 0x00100A00) == .init(keyCode: 16, isPressed: true))
    #expect(MediaKeyEvent(data1: 0x00100B00) == .init(keyCode: 16, isPressed: false))
}

@Test func decodesNextTrackKeyUsedByF9() {
    #expect(MediaKeyEvent(data1: 0x00110A00) == .init(keyCode: 17, isPressed: true))
}

@Test func ignoresRepeatedAndUnknownMediaStates() {
    #expect(MediaKeyEvent(data1: 0x00100C00) == nil)
    #expect(MediaKeyEvent(data1: 0x00100000) == nil)
}

@Test func mapsFunctionKeysToTheirMediaKeyCodes() {
    #expect(PushToTalkKey.f8.mediaKeyCode == 16)
    #expect(PushToTalkKey.f9.mediaKeyCode == 17)
    #expect(PushToTalkKey.rightOption.mediaKeyCode == nil)
}
