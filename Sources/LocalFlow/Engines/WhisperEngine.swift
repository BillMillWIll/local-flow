import Foundation
import LocalFlowCore

struct WhisperEngine: TranscriptionEngine {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Self.transcribeSync(audioURL: audioURL, options: options)
        }.value
    }

    private static func transcribeSync(audioURL: URL, options: TranscriptionOptions) throws -> String {
        let executableURL = try EngineRuntime.executable(named: "whisper-cli")
        guard ModelInstaller.isInstalled(ModelCatalog.whisperTurbo) else {
            throw LocalFlowError.missingModel
        }

        let vadURL = ModelInstaller.modelURL(for: ModelCatalog.sileroVAD)
        let vadPath = ModelInstaller.isInstalled(ModelCatalog.sileroVAD) ? vadURL.path : nil
        let outputURL = EngineRuntime.transcriptOutputURL(prefix: "whisper")
        let invocation = WhisperInvocation(
            modelPath: ModelInstaller.modelURL(for: ModelCatalog.whisperTurbo).path,
            audioPath: audioURL.path,
            outputPath: outputURL.path,
            prompt: CustomWords.whisperPrompt(options.customWords),
            vadModelPath: vadPath
        )

        try EngineRuntime.run(executableURL, arguments: invocation.arguments)
        return try EngineRuntime.readTranscript(outputPath: outputURL)
    }
}
