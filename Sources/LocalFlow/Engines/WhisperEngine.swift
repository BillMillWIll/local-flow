import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

enum WhisperTranscriber {
    static func transcribe(audioURL: URL, model: WhisperModel) throws -> String {
        let bundledExecutableURL = Bundle.main.url(
            forResource: "whisper-cli",
            withExtension: nil,
            subdirectory: "whisper/bin"
        )
        let executableURL = bundledExecutableURL
            ?? URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LocalFlowError.missingWhisper
        }

        let modelURL = ModelInstaller.modelURL(for: model)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalFlowError.missingModel
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-transcript")
        let textURL = outputURL.appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: textURL)

        let invocation = WhisperInvocation(
            modelPath: modelURL.path,
            audioPath: audioURL.path,
            outputPath: outputURL.path
        )
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = invocation.arguments
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalFlowError.transcriptionFailed(details)
        }

        let transcript = try String(contentsOf: textURL, encoding: .utf8)
        let cleaned = TranscriptCleaner.clean(transcript)
        guard !cleaned.isEmpty else {
            throw LocalFlowError.emptyTranscript
        }
        return cleaned
    }
}
