import Testing
@testable import LocalFlowCore

@Test func transcriptHistoryKeepsNewestFiveEntries() {
    var history = TranscriptHistory()

    for index in 1...6 {
        history.record("Text \(index)")
    }

    #expect(history.entries == [
        "Text 6",
        "Text 5",
        "Text 4",
        "Text 3",
        "Text 2"
    ])
}

@Test func transcriptHistoryIgnoresEmptyEntries() {
    var history = TranscriptHistory(entries: ["Vorher"])

    history.record("   ")

    #expect(history.entries == ["Vorher"])
}

@Test func transcriptHistoryRestoresFromSavedEntriesWithLimit() {
    let history = TranscriptHistory(entries: [
        "A",
        "B",
        "",
        "C",
        "D",
        "E",
        "F"
    ])

    #expect(history.entries == ["A", "B", "C", "D", "E"])
    #expect(history.latest == "A")
}

@Test func transcriptHistoryProvidesNumberedDisplayItems() {
    let history = TranscriptHistory(entries: [
        "Erster kurzer Text",
        "Zweiter kurzer Text"
    ])

    #expect(history.displayItems == [
        "1. Erster kurzer Text",
        "2. Zweiter kurzer Text"
    ])
}
