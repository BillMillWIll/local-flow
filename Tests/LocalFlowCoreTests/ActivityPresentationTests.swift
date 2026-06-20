import Testing
@testable import LocalFlowCore

@Test func presentsCoreAppActivitiesConsistently() {
    #expect(LocalFlowActivity.ready(keyTitle: "Rechte Wahltaste (⌥)").title == "Bereit")
    #expect(LocalFlowActivity.ready(keyTitle: "Rechte Wahltaste (⌥)").detail == "Rechte Wahltaste (⌥) halten und sprechen")
    #expect(LocalFlowActivity.recording.title == "Aufnahme läuft")
    #expect(LocalFlowActivity.recording.symbolName == "waveform.circle.fill")
    #expect(LocalFlowActivity.recording.isPulsing)
    #expect(LocalFlowActivity.testRecording.title == "Testaufnahme läuft")
    #expect(LocalFlowActivity.testRecording.detail == "Vier Sekunden sprechen")
    #expect(LocalFlowActivity.processing.title == "Wird transkribiert")
    #expect(LocalFlowActivity.success("Eingefügt").tone == .success)
    #expect(LocalFlowActivity.failure("Mikrofon fehlt").tone == .warning)
}

@Test func presentsKnownAndUnknownModelDownloadProgress() {
    #expect(LocalFlowActivity.downloadingModel(42).title == "Sprachmodell wird geladen · 42 %")
    #expect(LocalFlowActivity.downloadingModel(nil).title == "Sprachmodell wird geladen")
}
