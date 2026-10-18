import Foundation

/// A preferred spelling, optionally paired with one observed recognition error.
public struct DictionaryEntry: Codable, Equatable, Sendable {
    public var word: String
    public var heard: String

    public init(word: String, heard: String = "") {
        self.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        self.heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PersonalDictionary: Codable, Equatable, Sendable {
    public var entries: [DictionaryEntry]

    public init(entries: [DictionaryEntry] = []) {
        self.entries = entries
    }

    public init(legacyWords: String) {
        entries = CustomWords.parse(legacyWords).map { DictionaryEntry(word: $0) }
    }

    public var promptWords: [String] {
        var seen = Set<String>()
        return entries.map(\.word).filter { seen.insert(Self.key($0)).inserted }
    }

    public func addingWords(from text: String) -> PersonalDictionary {
        var next = self
        for word in CustomWords.parse(text) where next.validationMessage(word: word) == nil {
            // A word already present with an alias needs no additional spelling row.
            if !next.promptWords.contains(where: { Self.key($0) == Self.key(word) }) {
                next.entries.append(DictionaryEntry(word: word))
            }
        }
        return next
    }

    public func apply(to text: String) -> String {
        let aliases = entries.filter { !$0.heard.isEmpty }.map {
            ReplacementRule(match: $0.heard, replacement: $0.word)
        }
        let spelling = promptWords.map { ReplacementRule(match: $0, replacement: $0) }
        return ReplacementRules.apply(aliases + spelling, to: text)
    }

    /// A source may only resolve to one spelling. The same spelling can have
    /// several observed errors, entered individually without separators.
    public func validationMessage(word: String, heard: String = "", ignoring index: Int? = nil) -> String? {
        let candidate = DictionaryEntry(word: word, heard: heard)
        guard !candidate.word.isEmpty else { return "Bitte die gewünschte Schreibweise eingeben." }
        guard !candidate.word.contains(where: \.isNewline), !candidate.heard.contains(where: \.isNewline) else {
            return "Bitte nur ein Wort oder eine Wortgruppe pro Eintrag eingeben."
        }
        for (offset, entry) in entries.enumerated() where offset != index {
            if Self.key(entry.word) == Self.key(candidate.word), entry.word != candidate.word {
                return "Für dieses Wort ist „\(entry.word)“ gespeichert. Verwende dieselbe Groß- und Kleinschreibung."
            }
            if Self.key(entry.word) == Self.key(candidate.word), Self.key(entry.heard) == Self.key(candidate.heard) {
                return "Dieser Eintrag ist bereits gespeichert."
            }
            let sources = [entry.word, entry.heard].filter { !$0.isEmpty }.map(Self.key)
            let candidateSources = [candidate.word, candidate.heard].filter { !$0.isEmpty }.map(Self.key)
            if Self.key(entry.word) != Self.key(candidate.word), !Set(sources).isDisjoint(with: candidateSources) {
                return "Diese Schreibweise gehört bereits zu „\(entry.word)“. Bitte den vorhandenen Eintrag bearbeiten."
            }
        }
        return nil
    }

    private static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
