import Foundation
import LocalFlowCore

struct ParakeetEngine: TranscriptionEngine {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Self.transcribeSync(audioURL: audioURL)
        }.value
    }

    private static func transcribeSync(audioURL: URL) throws -> String {
        let executableURL = try EngineRuntime.executable(named: "parakeet-cli")
        guard ModelInstaller.isInstalled(ModelCatalog.parakeetV3) else {
            throw LocalFlowError.missingModel
        }

        let outputURL = EngineRuntime.transcriptOutputURL(prefix: "parakeet")
        let invocation = ParakeetInvocation(
            modelPath: ModelInstaller.modelURL(for: ModelCatalog.parakeetV3).path,
            audioPath: audioURL.path,
            outputPath: outputURL.path
        )

        try EngineRuntime.run(executableURL, arguments: invocation.arguments)
        return try EngineRuntime.readTranscript(outputPath: outputURL)
    }
}
