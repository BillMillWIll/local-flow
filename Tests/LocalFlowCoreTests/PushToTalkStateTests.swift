import Testing
@testable import LocalFlowCore

@Test func startsAndStopsNormalRecording() {
    var state = PushToTalkState()

    #expect(state.press() == .startRecording)
    #expect(state.recordingDidStart() == .none)
    #expect(state.release() == .stopRecording)
}

@Test func stopsImmediatelyWhenReleasedWhileRecordingStarts() {
    var state = PushToTalkState()

    #expect(state.press() == .startRecording)
    #expect(state.release() == .none)
    #expect(state.recordingDidStart() == .stopRecording)
}

@Test func ignoresPressWhileProcessing() {
    var state = PushToTalkState()

    _ = state.press()
    _ = state.recordingDidStart()
    _ = state.release()

    #expect(state.press() == .none)
    state.processingDidFinish()
    #expect(state.press() == .startRecording)
}
