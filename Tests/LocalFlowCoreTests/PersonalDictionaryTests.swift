import Foundation
import Testing
@testable import LocalFlowCore

@Test func migratesCommaListWithoutLosingWords() throws {
    let dictionary = PersonalDictionary(legacyWords: "Claude, Grok, GrokBot,\nclaude")
    #expect(dictionary.entries.map(\.word) == ["Claude", "Grok", "GrokBot"])
    #expect(dictionary.entries.allSatisfy { $0.heard.isEmpty })
    let data = try JSONEncoder().encode(dictionary)
    #expect(try JSONDecoder().decode(PersonalDictionary.self, from: data) == dictionary)
}

@Test func acceptsPastedWordListsWithDifferentLineEndings() {
    #expect(CustomWords.parse("Claude\r\nGrok\rArtMotion\u{2028}ChatGPT") == ["Claude", "Grok", "ArtMotion", "ChatGPT"])
}

@Test func preservesSpokenCommandsDuringCleanup() {
    let original = "Ich schreibe dir absatz vielen Dank mfg"
    #expect(CleanupGuard.accept(original: original, cleaned: "Ich schreibe dir vielen Dank.", protectedCommands: ["Absatz", "mfg"]) == original)
    #expect(CleanupGuard.accept(original: "Hallo neue  Zeile bis morgen", cleaned: "Hallo Neue Zeile bis morgen.", protectedCommands: ["neue Zeile"]) == "Hallo Neue Zeile bis morgen.")
}

@Test func rejectsInconsistentSpellingForAnotherVariant() {
    let dictionary = PersonalDictionary(entries: [.init(word: "grokbot", heard: "Grok Bot")])
    #expect(dictionary.validationMessage(word: "Grokbot", heard: "Grock Bot") != nil)
}

@Test func matchesPastedDecomposedUmlauts() {
    let dictionary = PersonalDictionary(entries: [.init(word: "BüroPilot", heard: "Büro Pilot")])
    #expect(dictionary.apply(to: "bu\u{308}ro Pilot") == "BüroPilot")
}

@Test func importsSeveralWordsWithoutDuplicatesOrConflicts() {
    let dictionary = PersonalDictionary(entries: [.init(word: "GrokBot", heard: "Grok Bot")])
    let imported = dictionary.addingWords(from: "Claude\nArtMotion\nclaude\nGrok Bot")
    #expect(imported.promptWords == ["GrokBot", "Claude", "ArtMotion"])
}

@Test func correctsKnownVariantsAndSpellingOnEveryEngine() {
    let dictionary = PersonalDictionary(entries: [
        .init(word: "grokbot", heard: "Grok Bot"),
        .init(word: "ArtMotion"),
        .init(word: "ChatGPT", heard: "Chat GPT")
    ])
    #expect(dictionary.apply(to: "GROK BOT und artmotion nutzen Chat  GPT.") == "grokbot und ArtMotion nutzen ChatGPT.")
    #expect(dictionary.apply(to: "Grokbot bleibt grokbot.") == "grokbot bleibt grokbot.")
    #expect(dictionary.promptWords == ["grokbot", "ArtMotion", "ChatGPT"])
}

@Test func correctsReportedGrokbotErrorsWithoutTouchingOtherWords() {
    let dictionary = PersonalDictionary(entries: [
        .init(word: "GrokBot", heard: "Crockbot"),
        .init(word: "GrokBot", heard: "Krugbot"),
        .init(word: "GrokBot", heard: "Grockbot")
    ])
    #expect(dictionary.apply(to: "Crockbot. Krugbot, GROCKBOT und grokbot.") == "GrokBot. GrokBot, GrokBot und GrokBot.")
    #expect(dictionary.apply(to: "Crockbot2 und Krugbotik") == "Crockbot2 und Krugbotik")
}

@Test func validatesConflictingDictionaryEntries() {
    let dictionary = PersonalDictionary(entries: [.init(word: "grokbot", heard: "Grok Bot")])
    #expect(dictionary.validationMessage(word: "  ", heard: "Grok") != nil)
    #expect(dictionary.validationMessage(word: "Anderes", heard: "grok bot") != nil)
    #expect(dictionary.validationMessage(word: "Grok Bot") != nil)
    #expect(dictionary.validationMessage(word: "grokbot", heard: "grok bot") != nil)
    #expect(dictionary.validationMessage(word: "grokbot", heard: "Grockbot") == nil)
    #expect(dictionary.validationMessage(word: "grokbot", heard: "Grok Bot", ignoring: 0) == nil)
}

@Test func replacementsDoNotCascadeOrChangeIdentifiers() {
    let rules = [ReplacementRule(match: "Grok", replacement: "Grok Bot"),
                 ReplacementRule(match: "Grok Bot", replacement: "grokbot")]
    #expect(ReplacementRules.apply(rules, to: "Grok Bot und Grok.") == "grokbot und Grok Bot.")
    #expect(ReplacementRules.apply([.init(match: "Grok", replacement: "grok")], to: "Grok2 _Grok Grokhaus Grok.") == "Grok2 _Grok Grokhaus grok.")
    #expect(ReplacementRules.apply([.init(match: "Cafe", replacement: "Kaffee")], to: "Cafe\u{301}") == "Cafe\u{301}")
}

@Test func cleanupCannotRewriteProtectedNamesOrRemoveParagraphs() {
    #expect(CleanupGuard.accept(original: "Nutze grokbot für die nächste Aufgabe.", cleaned: "Nutze Grok Bot für die nächste Aufgabe.", protectedTerms: ["grokbot"]) == "Nutze grokbot für die nächste Aufgabe.")
    #expect(CleanupGuard.accept(original: "Grokbot", cleaned: "Ein ganz anderer Satz.", protectedTerms: ["Grokbot"]) == "Grokbot")
    #expect(CleanupGuard.accept(original: "Hallo\n\nBis morgen", cleaned: "Hallo Bis morgen") == "Hallo\n\nBis morgen")
    #expect(CleanupGuard.accept(original: "Hallo", cleaned: "Hier ist ein langer Text, der mit dem Diktat nichts zu tun hat.") == "Hallo")
}

@Test func correctionsSurviveCleanupAndCommandsRunLast() {
    let dictionary = PersonalDictionary(entries: [.init(word: "grokbot", heard: "Grok Bot")])
    let prepared = dictionary.apply(to: "Grok Bot neue Zeile Bis morgen")
    let safe = CleanupGuard.accept(original: prepared, cleaned: "Grok Bot neue Zeile. Bis morgen.", protectedTerms: dictionary.promptWords)
    #expect(ReplacementRules.apply(ReplacementRules.parse(ReplacementRules.defaultText), to: safe) == "grokbot\nBis morgen")
}
