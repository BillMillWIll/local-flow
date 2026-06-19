import Testing
@testable import LocalFlowCore

@Test func usesSystemDefaultMicrophoneByDefault() {
    let selection = MicrophoneSelection(savedValue: nil)

    #expect(selection == .systemDefault)
    #expect(selection.rawValue == "systemDefault")
    #expect(selection.title == "Systemstandard verwenden")
    #expect(selection.deviceID == nil)
}

@Test func storesManualMicrophoneSelection() {
    let selection = MicrophoneSelection.manual(
        deviceID: "BuiltInMicDevice",
        name: "MacBook Pro Mikrofon"
    )

    #expect(selection.rawValue == "manual:BuiltInMicDevice:MacBook Pro Mikrofon")
    #expect(selection.title == "MacBook Pro Mikrofon")
    #expect(selection.deviceID == "BuiltInMicDevice")
}

@Test func restoresManualMicrophoneSelectionFromSavedValue() {
    let selection = MicrophoneSelection(
        savedValue: "manual:AirPods123:AirPods von Bill"
    )

    #expect(selection == .manual(deviceID: "AirPods123", name: "AirPods von Bill"))
    #expect(selection.deviceID == "AirPods123")
}

@Test func fallsBackToSystemDefaultForInvalidMicrophoneSelection() {
    #expect(MicrophoneSelection(savedValue: "manual:missingName") == .systemDefault)
    #expect(MicrophoneSelection(savedValue: "unknown") == .systemDefault)
}
