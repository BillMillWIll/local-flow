import Foundation

/// One user-defined text replacement, applied after recognition.
public struct ReplacementRule: Equatable, Sendable {
    public let match: String
    public let replacement: String

    public init(match: String, replacement: String) {
        self.match = match
        self.replacement = replacement
    }
}

public enum ReplacementRules {
    private static func pattern(for match: String) -> String {
        let phrase = match.precomposedStringWithCanonicalMapping.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "[\\p{Zs}\\t]+")
        return "(?<![\\p{L}\\p{M}\\p{N}_])(?:\(phrase))(?![\\p{L}\\p{M}\\p{N}_])"
    }

    public static func countMatches(of phrase: String, in text: String, caseSensitive: Bool = false) -> Int {
        guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern(for: phrase), options: caseSensitive ? [] : [.caseInsensitive]) else { return 0 }
        let normalized = text.precomposedStringWithCanonicalMapping
        return regex.numberOfMatches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
    }

    /// Rules every new installation starts with. Users can edit or delete them.
    public static let defaultText = """
    neue Zeile = \\n
    Absatz = \\n\\n
    """

    /// Parses one rule per line in the form `gehört = gewünscht`.
    /// Empty lines and lines starting with `#` are ignored. `\\n` in the
    /// replacement stands for a line break.
    public static func parse(_ text: String) -> [ReplacementRule] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            guard let separator = trimmed.range(of: "=") else { return nil }

            let match = trimmed[..<separator.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let replacement = trimmed[separator.upperBound...]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\n", with: "\n")
            guard !match.isEmpty else { return nil }
            return ReplacementRule(match: match, replacement: replacement)
        }
    }

    /// Applies the rules case-insensitively on whole words. Whitespace around
    /// inserted line breaks is removed so dictated "neue Zeile" produces a
    /// clean break.
    public static func apply(_ rules: [ReplacementRule], to text: String) -> String {
        let text = text.precomposedStringWithCanonicalMapping
        // Match against the original only: replacements must never trigger
        // other replacements. Longer phrases take precedence over their words.
        let ordered = rules.enumerated().filter { !$0.element.match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted {
            if $0.element.match.count == $1.element.match.count { return $0.offset < $1.offset }
            return $0.element.match.count > $1.element.match.count
        }.map(\.element)
        guard !ordered.isEmpty else { return text }
        let patterns = ordered.map { "(" + pattern(for: $0.match) + ")" }
        guard let regex = try? NSRegularExpression(
            pattern: patterns.joined(separator: "|"),
            options: [.caseInsensitive]
        ) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let index = ordered.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: ordered[index].replacement)
        }

        guard result.contains("\n") else { return result }
        let lines = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n[.,;:]\\s*", with: "\n", options: .regularExpression)
    }
}

public enum CustomWords {
    /// Accepts words separated by commas or line breaks; trims and de-duplicates.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Whisper initial prompt that biases spelling toward the user's words.
    public static func whisperPrompt(_ words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        return "Begriffe: " + words.joined(separator: ", ") + "."
    }
}

public enum RecordingGuard {
    /// Shorter recordings are almost always accidental taps; Whisper would
    /// hallucinate subtitle credits for them.
    public static let minimumDuration: TimeInterval = 0.4
    public static let maximumDuration: TimeInterval = 300

    public static func isLongEnough(_ duration: TimeInterval) -> Bool {
        duration >= minimumDuration
    }
}

public enum CleanupGuard {
    /// Accepts an LLM-cleaned transcript only when it is plausibly the same
    /// text; otherwise the raw transcript is kept so nothing is lost.
    public static func accept(original: String, cleaned: String, protectedTerms: [String] = [], protectedCommands: [String] = []) -> String {
        var trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models sometimes echo the prompt label or wrap the answer in quotes.
        if let range = trimmed.range(of: "^Text:\\s*", options: .regularExpression) {
            trimmed.removeSubrange(range)
        }
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("„", "“"), ("“", "”"), ("»", "«"), ("«", "»")]
        for (open, close) in quotePairs
        where trimmed.count > 1 && trimmed.first == open && trimmed.last == close
            && !original.hasPrefix(String(open)) {
            trimmed = String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return original }

        // Names and explicit paragraphs are user intent, not stylistic choices.
        for term in protectedTerms where !term.isEmpty {
            guard ReplacementRules.countMatches(of: term, in: original, caseSensitive: true)
                == ReplacementRules.countMatches(of: term, in: trimmed, caseSensitive: true) else { return original }
        }
        for command in protectedCommands {
            guard ReplacementRules.countMatches(of: command, in: original)
                == ReplacementRules.countMatches(of: command, in: trimmed) else { return original }
        }
        if original.contains("\n"), original.filter({ $0 == "\n" }).count != trimmed.filter({ $0 == "\n" }).count {
            return original
        }

        let originalCount = Double(original.count)
        let ratio = Double(trimmed.count) / originalCount
        guard (0.4...1.6).contains(ratio) else { return original }
        return trimmed
    }
}
