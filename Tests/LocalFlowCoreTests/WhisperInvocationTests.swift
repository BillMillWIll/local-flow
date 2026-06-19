import Testing
@testable import LocalFlowCore

@Test func buildsGermanWhisperArguments() {
    let invocation = WhisperInvocation(
        modelPath: "/models/ggml-small.bin",
        audioPath: "/tmp/input.wav",
        outputPath: "/tmp/result"
    )

    #expect(invocation.arguments == [
        "-m", "/models/ggml-small.bin",
        "-f", "/tmp/input.wav",
        "-l", "de",
        "-otxt",
        "-of", "/tmp/result",
        "-np"
    ])
}

@Test func usesRequestedLanguage() {
    let invocation = WhisperInvocation(
        modelPath: "model.bin",
        audioPath: "input.wav",
        outputPath: "result",
        language: "en"
    )

    #expect(invocation.arguments.contains(["-l", "en"]))
}

private extension Array where Element: Equatable {
    func contains(_ elements: [Element]) -> Bool {
        guard !elements.isEmpty, elements.count <= count else { return false }

        return indices.contains { start in
            let end = index(start, offsetBy: elements.count, limitedBy: endIndex)
            guard let end else { return false }
            return Array(self[start..<end]) == elements
        }
    }
}
