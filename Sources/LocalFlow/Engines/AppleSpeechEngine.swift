import AVFoundation
import Foundation
import LocalFlowCore
import Speech

/// Availability of Apple's on-device German speech recognition (macOS 26).
enum AppleSpeechSupport {
    static let locale = Locale(identifier: "de-DE")

    static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    static func isGermanInstalled() async -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { Self.matches($0) }
    }

    static func isGermanSupported() async -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { Self.matches($0) }
    }

    /// Downloads Apple's German language asset if it is missing.
    static func installGerman(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        guard #available(macOS 26.0, *) else {
            throw LocalFlowError.appleSpeechUnavailable
        }
        guard await isGermanSupported() else {
            throw LocalFlowError.appleSpeechUnavailable
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            return
        }

        let watcher = Task {
            while !Task.isCancelled {
                let fraction = request.progress.fractionCompleted
                progress(ModelDownloadProgress(
                    receivedBytes: Int64(fraction * 1000),
                    totalBytes: 1000
                ))
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
    }

    private static func matches(_ candidate: Locale) -> Bool {
        candidate.identifier(.bcp47).lowercased() == "de-de"
    }
}

@available(macOS 26.0, *)
struct AppleSpeechEngine: TranscriptionEngine {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
        let transcriber = SpeechTranscriber(
            locale: AppleSpeechSupport.locale,
            preset: .transcription
        )
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)

        async let collected: String = Self.collect(transcriber)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return TranscriptCleaner.clean(try await collected)
    }

    private static func collect(_ transcriber: SpeechTranscriber) async throws -> String {
        var text = ""
        for try await result in transcriber.results where result.isFinal {
            text += String(result.text.characters)
        }
        return text
    }
}
