import Foundation
import LocalFlowCore

struct TranscriptionOptions: Sendable {
    let customWords: [String]
}

protocol TranscriptionEngine: Sendable {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String
}

enum EngineFactory {
    static func make(_ engine: RecognitionEngine) -> any TranscriptionEngine {
        switch engine {
        case .apple:
            if #available(macOS 26.0, *) {
                return AppleSpeechEngine()
            }
            return ParakeetEngine()
        case .parakeet:
            return ParakeetEngine()
        case .whisperTurbo:
            return WhisperEngine()
        }
    }
}

/// Locates the bundled whisper.cpp runtime and runs its command-line tools.
enum EngineRuntime {
    private static var bundledRuntimeDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("whisper", isDirectory: true)
    }

    static func executable(named name: String) throws -> URL {
        let bundled = bundledRuntimeDirectory?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(name)
        let candidates = [bundled, URL(fileURLWithPath: "/opt/homebrew/bin/\(name)")]
        for candidate in candidates.compactMap({ $0 })
        where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw LocalFlowError.missingWhisper
    }

    /// ggml loads its Metal and CPU backends at runtime and searches next to
    /// the executable, which is why the build script places them in `bin`.
    static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static func run(_ executableURL: URL, arguments: [String]) throws {
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal {
                throw LocalFlowError.transcriptionFailed(
                    "\(executableURL.lastPathComponent) ist abgestürzt (Signal \(process.terminationStatus))."
                )
            }
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("load_backend") && !$0.hasPrefix("ggml_") }
                .suffix(3)
                .joined(separator: " ")
            throw LocalFlowError.transcriptionFailed(details)
        }
    }

    static func transcriptOutputURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-\(prefix)-\(UUID().uuidString)")
    }

    /// Reads, cleans and deletes the tool's text output.
    static func readTranscript(outputPath: URL) throws -> String {
        let textURL = outputPath.appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: textURL) }
        let transcript = try String(contentsOf: textURL, encoding: .utf8)
        return TranscriptCleaner.clean(transcript)
    }
}
