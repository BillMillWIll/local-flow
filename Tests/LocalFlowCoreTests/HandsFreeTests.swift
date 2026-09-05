import Testing
@testable import LocalFlowCore

@Test func detectsDoubleTapOnlyForQuickSecondPress() {
    var detector = DoubleTapDetector()

    let result1 = detector.press(at: 0)
    #expect(!result1)
    detector.release(at: 0.1)
    let result2 = detector.press(at: 0.3)
    #expect(result2)

    detector.release(at: 0.4)
    let result3 = detector.press(at: 0.5)
    #expect(!result3)
}

@Test func ignoresDoubleTapAfterLongHoldOrLongPause() {
    var detector = DoubleTapDetector()

    _ = detector.press(at: 0)
    detector.release(at: 2)
    let result4 = detector.press(at: 2.1)
    #expect(!result4)

    detector.release(at: 2.2)
    let result5 = detector.press(at: 3.5)
    #expect(!result5)
}

@Test func handsFreeRecordingKeepsRunningUntilNextPress() {
    var state = PushToTalkState()

    #expect(state.press() == .startRecording)
    state.enableHandsFree()
    #expect(state.recordingDidStart() == .none)
    #expect(state.release() == .none)
    #expect(state.isRecording)
    #expect(state.isHandsFree)

    #expect(state.press() == .stopRecording)
    #expect(!state.isHandsFree)
    state.processingDidFinish()
    #expect(state.press() == .startRecording)
}

@Test func cancelDropsRecordingAndLaterReleaseIsIgnored() {
    var state = PushToTalkState()

    _ = state.press()
    _ = state.recordingDidStart()
    let result6 = state.cancel()
    #expect(result6)
    #expect(!state.isRecording)
    #expect(state.release() == .none)
    let result7 = state.cancel()
    #expect(!result7)
    #expect(state.press() == .startRecording)
}

@Test func externalStopOnlyWorksWhileRecording() {
    var state = PushToTalkState()

    #expect(state.stop() == .none)
    _ = state.press()
    #expect(state.stop() == .none)
    _ = state.recordingDidStart()
    #expect(state.stop() == .stopRecording)
    #expect(state.release() == .none)
}

@Test func describesNewActivities() {
    #expect(LocalFlowActivity.handsFreeRecording.isPulsing)
    #expect(LocalFlowActivity.handsFreeRecording.tone == .recording)
    #expect(LocalFlowActivity.cleaning.tone == .accent)
    #expect(LocalFlowActivity.cancelled.title == "Abgebrochen")
    #expect(LocalFlowActivity.tooShort.tone == .warning)
}

@Test func secondTapWhileStartingTurnsPendingRecordingHandsFree() {
    var state = PushToTalkState()

    _ = state.press()
    #expect(state.release() == .none)
    state.enableHandsFree()
    #expect(state.isHandsFree)
    #expect(state.recordingDidStart() == .none)
    #expect(state.isRecording)
    #expect(state.press() == .stopRecording)
    #expect(state.isProcessing)
    state.processingDidFinish()
    #expect(state.isIdle)
}

