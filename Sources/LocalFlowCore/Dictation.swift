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
        var result = text
        for rule in rules {
            let pattern = "(?<!\\p{L})" + NSRegularExpression.escapedPattern(for: rule.match) + "(?!\\p{L})"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let template = NSRegularExpression.escapedTemplate(for: rule.replacement)
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
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
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
    public static func accept(original: String, cleaned: String) -> String {
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }

        let originalCount = Double(original.count)
        guard originalCount > 20 else { return trimmed }
        let ratio = Double(trimmed.count) / originalCount
        guard (0.4...1.6).contains(ratio) else { return original }
        return trimmed
    }
}
