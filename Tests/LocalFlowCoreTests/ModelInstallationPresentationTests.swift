import Testing
@testable import LocalFlowCore

@Test func presentsRetryStateAfterModelDownloadFailure() {
    let presentation = ModelInstallationPresentation.failed

    #expect(presentation.detail == "Download fehlgeschlagen – erneut versuchen")
    #expect(presentation.isButtonEnabled)
}
