import Testing
@testable import LocalFlowCore

@Test func removesWhisperNoiseAndNormalizesWhitespace() {
    let raw = "  [BLANK_AUDIO]\n Hallo,   das ist ein Test.  "

    #expect(TranscriptCleaner.clean(raw) == "Hallo, das ist ein Test.")
}

@Test func removesKnownNonSpeechMarkers() {
    let raw = "(Musik) [MUSIC] [Applause] Danke."

    #expect(TranscriptCleaner.clean(raw) == "Danke.")
}

@Test func returnsEmptyStringForNoiseOnlyTranscript() {
    #expect(TranscriptCleaner.clean("[BLANK_AUDIO]") == "")
}
