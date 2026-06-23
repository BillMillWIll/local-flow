import Testing
@testable import LocalFlowCore

@Test func invalidatesAnOlderDeferredResetWhenActivityChanges() {
    var reset = DeferredReset()
    let first = reset.schedule()

    reset.invalidate()

    #expect(!reset.isCurrent(first))
    let second = reset.schedule()
    #expect(reset.isCurrent(second))
}
