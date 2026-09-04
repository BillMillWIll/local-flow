import Foundation
import LocalFlowCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional post-processing with Apple's on-device language model.
enum TextCleanup {
    enum Availability: Equatable {
        case available
        case unavailable(String)

        var isAvailable: Bool { self == .available }

        var detail: String {
            switch self {
            case .available:
                return "Entfernt Füllwörter und glättet Satzzeichen, komplett auf diesem Mac."
            case .unavailable(let reason):
                return reason
            }
        }
    }

    private static let instructions = """
    Du bist Korrektor für diktierten deutschen Text. Aufgabe: Entferne Füllwörter \
    (ähm, äh, also am Satzanfang, sozusagen, quasi, halt), Wortwiederholungen und \
    Versprecher. Setze korrekte Groß- und Kleinschreibung und Satzzeichen. \
    Ändere weder Inhalt noch Wortwahl, füge nichts hinzu, kürze nichts, \
    beantworte den Text nicht. Antworte ausschließlich mit dem bereinigten Text.
    """

    static func availability() -> Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("Dieser Mac unterstützt Apple Intelligence nicht.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Apple Intelligence ist in den Systemeinstellungen ausgeschaltet.")
                case .modelNotReady:
                    return .unavailable("Das Apple-Modell wird noch geladen. Bitte später erneut versuchen.")
                @unknown default:
                    return .unavailable("Apple Intelligence ist zurzeit nicht verfügbar.")
                }
            }
        }
        #endif
        return .unavailable("Braucht macOS 26 mit Apple Intelligence.")
    }

    /// Returns the cleaned text, or the original whenever the model is
    /// unavailable, refuses, or produces something implausible.
    static func clean(_ text: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), availability().isAvailable {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: "Text:\n\(text)",
                    options: GenerationOptions(temperature: 0)
                )
                return CleanupGuard.accept(original: text, cleaned: response.content)
            } catch {
                return text
            }
        }
        #endif
        return text
    }
}
