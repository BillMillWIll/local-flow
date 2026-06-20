import Testing
@testable import LocalFlowCore

@Test func onboardingAdvancesInRequiredOrder() {
    var progress = OnboardingProgress()

    #expect(progress.completedStepCount == 0)
    #expect(progress.nextStep == .microphone)
    #expect(!progress.canFinish)

    progress.microphoneAllowed = true
    #expect(progress.nextStep == .accessibility)

    progress.accessibilityAllowed = true
    #expect(progress.nextStep == .model)

    progress.modelInstalled = true
    #expect(progress.nextStep == .testRecording)

    progress.testRecordingCompleted = true
    #expect(progress.completedStepCount == 4)
    #expect(progress.nextStep == nil)
    #expect(progress.canFinish)
}
