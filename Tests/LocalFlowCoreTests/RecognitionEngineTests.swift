import Testing
@testable import LocalFlowCore

@Test func prefersAppleWhenSupportedAndParakeetOtherwise() {
    #expect(RecognitionEngine.defaultEngine(appleSupported: true) == .apple)
    #expect(RecognitionEngine.defaultEngine(appleSupported: false) == .parakeet)
    #expect(RecognitionEngine.available(appleSupported: false) == [.parakeet, .whisperTurbo])
    #expect(RecognitionEngine.available(appleSupported: true) == [.apple, .parakeet, .whisperTurbo])
}

@Test func restoresSavedEngineAndMigratesLegacyWhisperSetting() {
    #expect(RecognitionEngine(savedValue: "parakeet", appleSupported: true) == .parakeet)
    #expect(RecognitionEngine(savedValue: nil, legacyWhisperModel: "largeTurbo", appleSupported: true) == .whisperTurbo)
    #expect(RecognitionEngine(savedValue: nil, legacyWhisperModel: "small", appleSupported: true) == .apple)
    #expect(RecognitionEngine(savedValue: nil, legacyWhisperModel: "small", appleSupported: false) == .parakeet)
    #expect(RecognitionEngine(savedValue: "unknown", appleSupported: false) == .parakeet)
}

@Test func neverReturnsAppleEngineOnOlderMacOS() {
    #expect(RecognitionEngine(savedValue: "apple", appleSupported: false) == .parakeet)
}

@Test func listsRequiredModelFilesPerEngine() {
    #expect(RecognitionEngine.apple.requiredFiles.isEmpty)
    #expect(RecognitionEngine.parakeet.requiredFiles == [ModelCatalog.parakeetV3])
    #expect(RecognitionEngine.whisperTurbo.requiredFiles == [ModelCatalog.whisperTurbo, ModelCatalog.sileroVAD])
    #expect(RecognitionEngine.whisperTurbo.supportsCustomWordPrompt)
    #expect(!RecognitionEngine.parakeet.supportsCustomWordPrompt)
}

@Test func pinsParakeetAndVadDownloads() {
    #expect(
        ModelCatalog.parakeetV3.downloadURL.absoluteString ==
        "https://huggingface.co/ggml-org/parakeet-GGUF/resolve/35156454d1a39de06863303dd209fd2bed6ee079/ggml-parakeet-tdt-0.6b-v3-q8_0.bin"
    )
    #expect(ModelCatalog.parakeetV3.sha256 == "4d64e9e96c2792186d072fde0034df0ad670cf680a2f53069052ead827fd600e")
    #expect(
        ModelCatalog.sileroVAD.downloadURL.absoluteString ==
        "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v5.1.2.bin"
    )
    #expect(ModelCatalog.sileroVAD.sha256 == "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf")
    #expect(ModelCatalog.file(named: "parakeet") == ModelCatalog.parakeetV3)
    #expect(ModelCatalog.file(named: "vad") == ModelCatalog.sileroVAD)
    #expect(ModelCatalog.file(named: "nope") == nil)
}

@Test func buildsParakeetArguments() {
    let invocation = ParakeetInvocation(modelPath: "/m.bin", audioPath: "/a.wav", outputPath: "/out")
    #expect(invocation.arguments == ["-m", "/m.bin", "-f", "/a.wav", "-otxt", "-of", "/out", "-np"])
}

@Test func addsPromptAndVadToWhisperArguments() {
    let invocation = WhisperInvocation(
        modelPath: "/m.bin",
        audioPath: "/a.wav",
        outputPath: "/out",
        prompt: "Begriffe: Cuban.",
        vadModelPath: "/vad.bin"
    )
    #expect(invocation.arguments.contains("--suppress-nst"))
    #expect(invocation.arguments.contains("--vad"))
    #expect(invocation.arguments.firstIndex(of: "--vad-model").map { invocation.arguments[$0 + 1] } == "/vad.bin")
    #expect(invocation.arguments.firstIndex(of: "--prompt").map { invocation.arguments[$0 + 1] } == "Begriffe: Cuban.")

    let plain = WhisperInvocation(modelPath: "/m.bin", audioPath: "/a.wav", outputPath: "/out")
    #expect(!plain.arguments.contains("--vad"))
    #expect(!plain.arguments.contains("--prompt"))
}
