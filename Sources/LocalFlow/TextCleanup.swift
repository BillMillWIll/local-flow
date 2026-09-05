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

    /// Loads the model ahead of the first dictation so the clean-up does not
    /// pay the start-up cost while the user waits.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), availability().isAvailable {
            Task.detached(priority: .utility) {
                await SessionStore.shared.prepareNext()
            }
        }
        #endif
    }

    /// Returns the cleaned text, or the original whenever the model is
    /// unavailable, refuses, or produces something implausible.
    static func clean(_ text: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), availability().isAvailable {
            let session = await SessionStore.shared.take()
            defer { Task.detached(priority: .utility) { await SessionStore.shared.prepareNext() } }
            do {
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

    #if canImport(FoundationModels)
    /// Every dictation gets a fresh session so earlier texts never leak into
    /// the next result. The next session is prepared in advance, which keeps
    /// the model and the instruction prefix warm.
    @available(macOS 26.0, *)
    private actor SessionStore {
        static let shared = SessionStore()
        private var next: LanguageModelSession?

        func take() -> LanguageModelSession {
            defer { next = nil }
            return next ?? LanguageModelSession(instructions: TextCleanup.instructions)
        }

        func prepareNext() {
            guard next == nil else { return }
            let session = LanguageModelSession(instructions: TextCleanup.instructions)
            session.prewarm()
            next = session
        }
    }
    #endif
}
