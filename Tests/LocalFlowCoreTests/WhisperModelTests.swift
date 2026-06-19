import Testing
@testable import LocalFlowCore

@Test func offersFastAndAccurateWhisperModels() {
    #expect(WhisperModel.allCases.map(\.title) == [
        "Small Q5_1 – schneller",
        "Large v3 Turbo Q5_0 – genauer"
    ])
}

@Test func mapsModelsToLocalFiles() {
    #expect(WhisperModel.small.fileName == "ggml-small-q5_1.bin")
    #expect(WhisperModel.largeTurbo.fileName == "ggml-large-v3-turbo-q5_0.bin")
}

@Test func mapsModelsToVerifiedDownloads() {
    #expect(
        WhisperModel.small.downloadURL.absoluteString ==
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin"
    )
    #expect(
        WhisperModel.small.sha256 ==
        "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
    )
    #expect(
        WhisperModel.largeTurbo.downloadURL.absoluteString ==
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin"
    )
    #expect(
        WhisperModel.largeTurbo.sha256 ==
        "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    )
}

@Test func formatsKnownAndUnknownDownloadProgress() {
    #expect(ModelDownloadProgress(receivedBytes: 50, totalBytes: 100).percentage == 50)
    #expect(ModelDownloadProgress(receivedBytes: 1, totalBytes: nil).percentage == nil)
    #expect(ModelDownloadProgress(receivedBytes: 120, totalBytes: 100).percentage == 100)
}

@Test func restoresSavedModelOrUsesSmallByDefault() {
    #expect(WhisperModel.defaultModel == .small)
    #expect(WhisperModel(savedValue: "largeTurbo") == .largeTurbo)
    #expect(WhisperModel(savedValue: "unknown") == .small)
    #expect(WhisperModel(savedValue: nil) == .small)
}
