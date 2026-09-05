import Foundation

/// A downloadable, checksum-verified model file.
public struct ModelFile: Equatable, Hashable, Sendable {
    public let fileName: String
    public let downloadURL: URL
    public let sha256: String
    public let sizeDescription: String

    public init(fileName: String, downloadURL: URL, sha256: String, sizeDescription: String) {
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.sizeDescription = sizeDescription
    }
}

public enum ModelCatalog {
    public static let whisperRevision = WhisperModel.repositoryRevision
    public static let parakeetRevision = "35156454d1a39de06863303dd209fd2bed6ee079"
    public static let vadRevision = "9ffd54a1e1ee413ddf265af9913beaf518d1639b"

    public static let whisperTurbo = ModelFile(
        fileName: WhisperModel.largeTurbo.fileName,
        downloadURL: WhisperModel.largeTurbo.downloadURL,
        sha256: WhisperModel.largeTurbo.sha256,
        sizeDescription: "550 MB"
    )

    public static let parakeetV3 = ModelFile(
        fileName: "ggml-parakeet-tdt-0.6b-v3-q8_0.bin",
        downloadURL: URL(
            string: "https://huggingface.co/ggml-org/parakeet-GGUF/resolve/\(parakeetRevision)/ggml-parakeet-tdt-0.6b-v3-q8_0.bin"
        )!,
        sha256: "4d64e9e96c2792186d072fde0034df0ad670cf680a2f53069052ead827fd600e",
        sizeDescription: "670 MB"
    )

    public static let sileroVAD = ModelFile(
        fileName: "ggml-silero-v5.1.2.bin",
        downloadURL: URL(
            string: "https://huggingface.co/ggml-org/whisper-vad/resolve/\(vadRevision)/ggml-silero-v5.1.2.bin"
        )!,
        sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf",
        sizeDescription: "1 MB"
    )

    /// Names accepted by the `--download-model` diagnostic.
    public static func file(named name: String) -> ModelFile? {
        switch name {
        case "parakeet":
            return parakeetV3
        case "whisperTurbo", "largeTurbo":
            return whisperTurbo
        case "vad":
            return sileroVAD
        case "small":
            return ModelFile(
                fileName: WhisperModel.small.fileName,
                downloadURL: WhisperModel.small.downloadURL,
                sha256: WhisperModel.small.sha256,
                sizeDescription: "190 MB"
            )
        default:
            return nil
        }
    }
}

/// The speech-to-text backend used for a dictation.
public enum RecognitionEngine: String, CaseIterable, Sendable {
    case apple
    case parakeet
    case whisperTurbo

    public var title: String {
        switch self {
        case .apple:
            return "Apple – neu, empfohlen"
        case .parakeet:
            return "Parakeet – neu, für Macs vor macOS 26"
        case .whisperTurbo:
            return "Whisper Turbo – bisherige Erkennung"
        }
    }

    public var shortTitle: String {
        switch self {
        case .apple:
            return "Apple"
        case .parakeet:
            return "Parakeet"
        case .whisperTurbo:
            return "Whisper Turbo"
        }
    }

    public var detail: String {
        switch self {
        case .apple:
            return "Die Spracherkennung von macOS 26. Am schnellsten, kein Download, erfindet bei Stille nichts. Eigene Wörter wirken nur über Ersetzungen."
        case .parakeet:
            return "NVIDIA-Modell, läuft lokal. Fast so schnell wie Apple, braucht einmalig 670 MB. Eigene Wörter wirken nur über Ersetzungen."
        case .whisperTurbo:
            return "Das Modell aus Version 1.x. Etwas langsamer, versteht eigene Wörter aus dem Tab „Text“ direkt."
        }
    }

    /// Files that must be present locally before this engine can run.
    public var requiredFiles: [ModelFile] {
        switch self {
        case .apple:
            return []
        case .parakeet:
            return [ModelCatalog.parakeetV3]
        case .whisperTurbo:
            return [ModelCatalog.whisperTurbo, ModelCatalog.sileroVAD]
        }
    }

    public var supportsCustomWordPrompt: Bool {
        self == .whisperTurbo
    }

    public var requiresAppleSpeech: Bool {
        self == .apple
    }

    public static func available(appleSupported: Bool) -> [RecognitionEngine] {
        allCases.filter { appleSupported || !$0.requiresAppleSpeech }
    }

    public static func defaultEngine(appleSupported: Bool) -> RecognitionEngine {
        appleSupported ? .apple : .parakeet
    }

    /// Restores a saved selection, migrates the pre-2.0 Whisper model setting,
    /// and never returns an engine the current macOS cannot run.
    public init(savedValue: String?, legacyWhisperModel: String? = nil, appleSupported: Bool) {
        if let savedValue, let saved = RecognitionEngine(rawValue: savedValue) {
            self = saved
        } else if legacyWhisperModel == "largeTurbo" {
            self = .whisperTurbo
        } else {
            self = Self.defaultEngine(appleSupported: appleSupported)
        }

        if requiresAppleSpeech, !appleSupported {
            self = Self.defaultEngine(appleSupported: false)
        }
    }
}

public struct ParakeetInvocation: Sendable {
    public let modelPath: String
    public let audioPath: String
    public let outputPath: String

    public init(modelPath: String, audioPath: String, outputPath: String) {
        self.modelPath = modelPath
        self.audioPath = audioPath
        self.outputPath = outputPath
    }

    public var arguments: [String] {
        [
            "-m", modelPath,
            "-f", audioPath,
            "-otxt",
            "-of", outputPath,
            "-np"
        ]
    }
}
