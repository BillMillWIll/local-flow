import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

enum LocalFlowError: LocalizedError {
    case microphoneDenied
    case recordingFailed
    case accessibilityDenied
    case missingWhisper
    case missingModel
    case modelDownloadFailed
    case modelChecksumFailed
    case transcriptionFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Mikrofonzugriff fehlt."
        case .recordingFailed:
            return "Die Aufnahme konnte nicht gestartet werden."
        case .accessibilityDenied:
            return "Bedienungshilfen-Zugriff fehlt."
        case .missingWhisper:
            return "whisper-cli wurde nicht gefunden."
        case .missingModel:
            return "Das lokale Whisper-Modell fehlt."
        case .modelDownloadFailed:
            return "Das Sprachmodell konnte nicht heruntergeladen werden."
        case .modelChecksumFailed:
            return "Die Sicherheitsprüfung des Sprachmodells ist fehlgeschlagen."
        case .transcriptionFailed(let details):
            return details.isEmpty ? "Die Transkription ist fehlgeschlagen." : details
        case .emptyTranscript:
            return "Keine Sprache erkannt."
        }
    }
}
