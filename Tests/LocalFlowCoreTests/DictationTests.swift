import Testing
@testable import LocalFlowCore

@Test func parsesReplacementRulesAndIgnoresComments() {
    let rules = ReplacementRules.parse("""
    # Kommentar
    Kluben = Cuban

    neue Zeile = \\n
    ohne gleich
    = leer
    """)

    #expect(rules == [
        ReplacementRule(match: "Kluben", replacement: "Cuban"),
        ReplacementRule(match: "neue Zeile", replacement: "\n")
    ])
}

@Test func appliesRulesCaseInsensitivelyOnWholeWords() {
    let rules = ReplacementRules.parse("kluben = Cuban\nTennis Kette = Tennis-Kette")
    let text = ReplacementRules.apply(rules, to: "Den KLUBEN und die tennis kette prüfen. Klubenhaus bleibt.")

    #expect(text == "Den Cuban und die Tennis-Kette prüfen. Klubenhaus bleibt.")
}

@Test func insertsCleanLineBreaks() {
    let rules = ReplacementRules.parse(ReplacementRules.defaultText)
    let text = ReplacementRules.apply(rules, to: "Hallo Bilal, neue Zeile. Wie geht es dir? Absatz Bis morgen.")

    #expect(text == "Hallo Bilal,\nWie geht es dir?\n\nBis morgen.")
}

@Test func parsesCustomWordsAndBuildsWhisperPrompt() {
    let words = CustomWords.parse("Cuban, Moissanite\nBABA, cuban ,, ")
    #expect(words == ["Cuban", "Moissanite", "BABA"])
    #expect(CustomWords.whisperPrompt(words) == "Begriffe: Cuban, Moissanite, BABA.")
    #expect(CustomWords.whisperPrompt([]) == nil)
}

@Test func rejectsAccidentalTaps() {
    #expect(!RecordingGuard.isLongEnough(0.2))
    #expect(RecordingGuard.isLongEnough(0.4))
    #expect(RecordingGuard.maximumDuration == 300)
}

@Test func keepsOriginalWhenCleanupLooksBroken() {
    let original = "ähm also ich schicke dir morgen die Shotlist für die neue Folge"
    #expect(CleanupGuard.accept(original: original, cleaned: "   ") == original)
    #expect(CleanupGuard.accept(original: original, cleaned: "Ok.") == original)
    #expect(CleanupGuard.accept(original: original, cleaned: String(repeating: "x", count: 200)) == original)
    #expect(CleanupGuard.accept(original: original, cleaned: "Ich schicke dir morgen die Shotlist für die neue Folge. ") == "Ich schicke dir morgen die Shotlist für die neue Folge.")
    #expect(CleanupGuard.accept(original: "Hallo", cleaned: "Hallo!") == "Hallo!")
}

@Test func removesWhisperSubtitleHallucinations() {
    #expect(TranscriptCleaner.clean("Untertitel im Auftrag des ZDF, 2020") == "")
    #expect(TranscriptCleaner.clean("Untertitelung des ZDF, 2020") == "")
    #expect(TranscriptCleaner.clean("Untertitel der Amara.org-Community") == "")
    #expect(TranscriptCleaner.clean("Bis morgen dann. Untertitelung des ZDF, 2020") == "Bis morgen dann.")
    #expect(TranscriptCleaner.clean("Vielen Dank für deine Nachricht.") == "Vielen Dank für deine Nachricht.")
    #expect(TranscriptCleaner.clean("Wir untertiteln das Video morgen.") == "Wir untertiteln das Video morgen.")
}
