import Testing
@testable import LocalFlowCore

@Test func restoresPasteboardOnlyWhenLocalFlowStillOwnsItsTemporaryContents() {
    #expect(
        PasteboardRestoration.shouldRestore(
            expectedChangeCount: 12,
            currentChangeCount: 12
        )
    )
    #expect(
        !PasteboardRestoration.shouldRestore(
            expectedChangeCount: 12,
            currentChangeCount: 13
        )
    )
}
