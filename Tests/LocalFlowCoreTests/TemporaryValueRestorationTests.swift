import Testing
@testable import LocalFlowCore

@Test func restoresATemporaryValueExactlyOnce() {
    var restoration = TemporaryValueRestoration<String>()

    restoration.remember("Systemmikrofon")

    #expect(restoration.takeRememberedValue() == "Systemmikrofon")
    #expect(restoration.takeRememberedValue() == nil)
}
