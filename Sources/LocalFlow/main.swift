import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore

private enum LocalFlowError: LocalizedError {
    case microphoneDenied
    case recordingFailed
    case accessibilityDenied
    case missingWhisper
    case missingModel
    case modelDownloadFailed
    case modelChecksumFailed
    case transcriptionFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Mikrofonzugriff fehlt."
        case .recordingFailed:
            return "Die Aufnahme konnte nicht gestartet werden."
        case .accessibilityDenied:
            return "Bedienungshilfen-Zugriff fehlt."
        case .missingWhisper:
            return "whisper-cli wurde nicht gefunden."
        case .missingModel:
            return "Das lokale Whisper-Modell fehlt."
        case .modelDownloadFailed:
            return "Das Sprachmodell konnte nicht heruntergeladen werden."
        case .modelChecksumFailed:
            return "Die Sicherheitsprüfung des Sprachmodells ist fehlgeschlagen."
        case .transcriptionFailed(let details):
            return details.isEmpty ? "Die Transkription ist fehlgeschlagen." : details
        case .emptyTranscript:
            return "Keine Sprache erkannt."
        }
    }
}

private enum ModelInstaller {
    static var modelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalFlow")
    }

    static func modelURL(for model: WhisperModel) -> URL {
        modelDirectory.appendingPathComponent(model.fileName)
    }

    static func isInstalled(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: model).path)
    }

    static func install(_ model: WhisperModel) async throws {
        if isInstalled(model) {
            return
        }

        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )

        let partialURL = modelURL(for: model).appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partialURL)

        let temporaryURL: URL
        do {
            (temporaryURL, _) = try await URLSession.shared.download(from: model.downloadURL)
        } catch {
            throw LocalFlowError.modelDownloadFailed
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
            let checksum = try await Task.detached {
                try Self.sha256(of: partialURL)
            }.value

            guard checksum == model.sha256 else {
                try? FileManager.default.removeItem(at: partialURL)
                throw LocalFlowError.modelChecksumFailed
            }

            try FileManager.default.moveItem(at: partialURL, to: modelURL(for: model))
        } catch let error as LocalFlowError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw LocalFlowError.modelDownloadFailed
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let data = try handle.read(upToCount: 1_048_576),
                  !data.isEmpty
            else {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var previousDefaultInputDeviceID: AudioDeviceID?

    func start(microphone: MicrophoneSelection) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw LocalFlowError.microphoneDenied
        }

        if let deviceID = microphone.deviceID {
            try switchDefaultInputDevice(to: deviceID)
        }

        let url = Self.recordingURL
        try? FileManager.default.removeItem(at: url)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            restoreDefaultInputDevice()
            throw LocalFlowError.recordingFailed
        }
        self.recorder = recorder
    }

    func stop() throws -> URL {
        guard let recorder else {
            throw LocalFlowError.recordingFailed
        }
        recorder.stop()
        self.recorder = nil
        restoreDefaultInputDevice()
        return recorder.url
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        restoreDefaultInputDevice()
    }

    private func switchDefaultInputDevice(to uniqueID: String) throws {
        guard var selectedDeviceID = Self.audioDeviceID(for: uniqueID) else {
            throw LocalFlowError.recordingFailed
        }

        let currentDeviceID = try Self.defaultInputDeviceID()
        previousDefaultInputDeviceID = currentDeviceID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &selectedDeviceID
        )

        if status != noErr {
            previousDefaultInputDeviceID = nil
            throw LocalFlowError.recordingFailed
        }
    }

    private func restoreDefaultInputDevice() {
        guard var deviceID = previousDefaultInputDeviceID else { return }
        previousDefaultInputDeviceID = nil

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        if status != noErr {
            throw LocalFlowError.recordingFailed
        }
        return deviceID
    }

    private static func audioDeviceID(for uniqueID: String) -> AudioDeviceID? {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return nil
        }

        return devices.first { deviceID in
            deviceUID(for: deviceID) == uniqueID
        }
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFTypeRef?>.size)
        let uidPointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFTypeRef?>.size,
            alignment: MemoryLayout<CFTypeRef?>.alignment
        )
        let typedUIDPointer = uidPointer.bindMemory(to: CFTypeRef?.self, capacity: 1)
        typedUIDPointer.initialize(to: nil)
        defer {
            typedUIDPointer.deinitialize(count: 1)
            uidPointer.deallocate()
        }
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            uidPointer
        )
        let uid = typedUIDPointer.pointee
        return status == noErr ? uid as? String : nil
    }

    private static var recordingURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-recording.wav")
    }
}

@MainActor
private final class PushToTalkMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPressed = false
    private var key: PushToTalkKey
    private let onPress: () -> Void
    private let onRelease: () -> Void

    init(
        key: PushToTalkKey,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.key = key
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        let events: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .keyUp, .systemDefined
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func updateKey(_ key: PushToTalkKey) {
        isPressed = false
        self.key = key
    }

    private func handle(_ event: NSEvent) {
        if event.type == .systemDefined {
            handleMediaKey(event)
            return
        }

        guard event.keyCode == key.keyCode else { return }

        let pressed: Bool
        if key.isModifier {
            guard event.type == .flagsChanged else { return }
            pressed = modifierIsPressed(in: event)
        } else {
            guard event.type == .keyDown || event.type == .keyUp else { return }
            guard !event.isARepeat else { return }
            pressed = event.type == .keyDown
        }

        updatePressedState(pressed)
    }

    private func handleMediaKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8,
              let expectedCode = key.mediaKeyCode,
              let mediaEvent = MediaKeyEvent(data1: event.data1),
              mediaEvent.keyCode == expectedCode
        else {
            return
        }

        updatePressedState(mediaEvent.isPressed)
    }

    private func updatePressedState(_ pressed: Bool) {
        if pressed, !isPressed {
            isPressed = true
            onPress()
        } else if !pressed, isPressed {
            isPressed = false
            onRelease()
        }
    }

    private func modifierIsPressed(in event: NSEvent) -> Bool {
        switch key.modifierKind {
        case .option:
            return event.modifierFlags.contains(.option)
        case .command:
            return event.modifierFlags.contains(.command)
        case .control:
            return event.modifierFlags.contains(.control)
        case .shift:
            return event.modifierFlags.contains(.shift)
        case .capsLock:
            return event.modifierFlags.contains(.capsLock)
        case .function:
            return event.modifierFlags.contains(.function)
        case .none:
            return false
        }
    }
}

private enum WhisperTranscriber {
    static func transcribe(audioURL: URL, model: WhisperModel) throws -> String {
        let bundledExecutableURL = Bundle.main.url(
            forResource: "whisper-cli",
            withExtension: nil,
            subdirectory: "whisper/bin"
        )
        let executableURL = bundledExecutableURL
            ?? URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LocalFlowError.missingWhisper
        }

        let modelURL = ModelInstaller.modelURL(for: model)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalFlowError.missingModel
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-transcript")
        let textURL = outputURL.appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: textURL)

        let invocation = WhisperInvocation(
            modelPath: modelURL.path,
            audioPath: audioURL.path,
            outputPath: outputURL.path
        )
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = invocation.arguments
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalFlowError.transcriptionFailed(details)
        }

        let transcript = try String(contentsOf: textURL, encoding: .utf8)
        let cleaned = TranscriptCleaner.clean(transcript)
        guard !cleaned.isEmpty else {
            throw LocalFlowError.emptyTranscript
        }
        return cleaned
    }
}

@MainActor
private enum TextInserter {
    static func paste(_ text: String) throws {
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            throw LocalFlowError.accessibilityDenied
        }

        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: false
        )
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        guard let snapshot else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let items = snapshot.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }

    static func promptForAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let keyValueLabel = NSTextField(labelWithString: "")
    private let learnKeyButton = NSButton()
    private let modelPopup = NSPopUpButton()
    private let microphonePopup = NSPopUpButton()
    private let testButton = NSButton()
    private let copyLatestButton = NSButton()
    private let historyButton = NSButton()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let permissionsLabel = NSTextField(wrappingLabelWithString: "")
    private var captureMonitor: Any?
    private let onKeyChanged: (PushToTalkKey) -> Void
    private let onModelChanged: (WhisperModel) -> Void
    private let onMicrophoneChanged: (MicrophoneSelection) -> Void
    private let onTestRecording: () -> Void
    private let onCopyLatestTranscript: () -> Void
    private let onCopyHistoryTranscript: (String) -> Void
    private var availableMicrophones: [MicrophoneSelection] = []
    private var transcriptHistory = TranscriptHistory()

    init(
        selectedKey: PushToTalkKey,
        selectedModel: WhisperModel,
        selectedMicrophone: MicrophoneSelection,
        onKeyChanged: @escaping (PushToTalkKey) -> Void,
        onModelChanged: @escaping (WhisperModel) -> Void,
        onMicrophoneChanged: @escaping (MicrophoneSelection) -> Void,
        onTestRecording: @escaping () -> Void,
        onCopyLatestTranscript: @escaping () -> Void,
        onCopyHistoryTranscript: @escaping (String) -> Void
    ) {
        self.onKeyChanged = onKeyChanged
        self.onModelChanged = onModelChanged
        self.onMicrophoneChanged = onMicrophoneChanged
        self.onTestRecording = onTestRecording
        self.onCopyLatestTranscript = onCopyLatestTranscript
        self.onCopyHistoryTranscript = onCopyHistoryTranscript

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Local Flow"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        configureContent(
            selectedKey: selectedKey,
            selectedModel: selectedModel,
            selectedMicrophone: selectedMicrophone
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func setSelectedKey(_ key: PushToTalkKey) {
        keyValueLabel.stringValue = key.title
    }

    func setPermissionsStatus(microphoneAllowed: Bool, accessibilityAllowed: Bool) {
        let microphone = microphoneAllowed ? "✓ Mikrofon" : "✗ Mikrofon"
        let accessibility = accessibilityAllowed ? "✓ Bedienungshilfen" : "✗ Bedienungshilfen"
        permissionsLabel.stringValue = "\(microphone)    \(accessibility)"
        permissionsLabel.textColor = microphoneAllowed && accessibilityAllowed
            ? .systemGreen
            : .systemOrange
    }

    func setTestResult(_ text: String) {
        resultLabel.stringValue = text
    }

    func setTestRecordingEnabled(_ enabled: Bool) {
        testButton.isEnabled = enabled
    }

    func setHasTranscriptHistory(_ hasHistory: Bool) {
        copyLatestButton.isEnabled = hasHistory
        historyButton.isEnabled = hasHistory
    }

    func setTranscriptHistory(_ history: TranscriptHistory) {
        transcriptHistory = history
        setHasTranscriptHistory(history.latest != nil)
    }

    func refreshMicrophones(selected: MicrophoneSelection) {
        availableMicrophones = Self.microphoneSelections()
        microphonePopup.removeAllItems()
        microphonePopup.addItems(withTitles: availableMicrophones.map(\.title))

        let selectedIndex = availableMicrophones.firstIndex(of: selected) ?? 0
        microphonePopup.selectItem(at: selectedIndex)
    }

    private func configureContent(
        selectedKey: PushToTalkKey,
        selectedModel: WhisperModel,
        selectedMicrophone: MicrophoneSelection
    ) {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "waveform.circle.fill",
            accessibilityDescription: "Local Flow"
        )!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .medium)

        let title = NSTextField(labelWithString: "Local Flow")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(
            wrappingLabelWithString: "Taste gedrückt halten, sprechen und loslassen. Der Text wird lokal in das aktive Textfeld eingefügt."
        )
        subtitle.textColor = .secondaryLabelColor

        let keyLabel = NSTextField(labelWithString: "Sprechtaste")
        keyLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        keyValueLabel.stringValue = selectedKey.title
        keyValueLabel.font = .systemFont(ofSize: 15, weight: .medium)

        learnKeyButton.title = "Taste anlernen"
        learnKeyButton.target = self
        learnKeyButton.action = #selector(startKeyCapture)
        learnKeyButton.bezelStyle = .rounded

        let modelLabel = NSTextField(labelWithString: "Sprachmodell")
        modelLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        modelPopup.addItems(withTitles: WhisperModel.allCases.map(\.title))
        modelPopup.selectItem(
            at: WhisperModel.allCases.firstIndex(of: selectedModel) ?? 0
        )
        modelPopup.target = self
        modelPopup.action = #selector(modelSelectionChanged)

        let microphoneLabel = NSTextField(labelWithString: "Mikrofon")
        microphoneLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneSelectionChanged)
        refreshMicrophones(selected: selectedMicrophone)

        testButton.title = "Aufnahme testen"
        testButton.target = self
        testButton.action = #selector(testRecording)
        testButton.bezelStyle = .rounded

        copyLatestButton.title = "Letzten Text kopieren"
        copyLatestButton.target = self
        copyLatestButton.action = #selector(copyLatestTranscript)
        copyLatestButton.bezelStyle = .rounded
        copyLatestButton.isEnabled = false

        historyButton.title = "Historie"
        historyButton.target = self
        historyButton.action = #selector(showTranscriptHistory)
        historyButton.bezelStyle = .rounded
        historyButton.isEnabled = false

        resultLabel.stringValue = "Noch kein Testtranskript."
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.maximumNumberOfLines = 4

        statusLabel.stringValue = "Bereit"
        statusLabel.textColor = .secondaryLabelColor
        permissionsLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let permissionsButton = NSButton(
            title: "Berechtigungen öffnen",
            target: self,
            action: #selector(openPrivacySettings)
        )
        permissionsButton.bezelStyle = .rounded

        let quitButton = NSButton(
            title: "Beenden",
            target: NSApp,
            action: #selector(NSApplication.terminate(_:))
        )
        quitButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [permissionsButton, quitButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let keyRow = NSStackView(views: [keyValueLabel, learnKeyButton])
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 12

        let actionRow = NSStackView(views: [testButton, copyLatestButton, historyButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10

        let stack = NSStackView(views: [
            icon, title, subtitle, keyLabel, keyRow, modelLabel, modelPopup,
            microphoneLabel, microphonePopup, actionRow, resultLabel,
            permissionsLabel, statusLabel, buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            keyValueLabel.widthAnchor.constraint(equalToConstant: 190),
            modelPopup.widthAnchor.constraint(equalToConstant: 360),
            microphonePopup.widthAnchor.constraint(equalToConstant: 360),
            resultLabel.widthAnchor.constraint(equalToConstant: 460)
        ])
    }

    @objc private func modelSelectionChanged() {
        guard modelPopup.indexOfSelectedItem >= 0 else { return }
        let model = WhisperModel.allCases[modelPopup.indexOfSelectedItem]
        onModelChanged(model)
        setStatus("Modell gespeichert: \(model.title)")
    }

    @objc private func microphoneSelectionChanged() {
        guard microphonePopup.indexOfSelectedItem >= 0 else { return }
        let microphone = availableMicrophones[microphonePopup.indexOfSelectedItem]
        onMicrophoneChanged(microphone)
        setStatus("Mikrofon gespeichert: \(microphone.title)")
    }

    @objc private func testRecording() {
        onTestRecording()
    }

    @objc private func copyLatestTranscript() {
        onCopyLatestTranscript()
    }

    @objc private func showTranscriptHistory() {
        let menu = NSMenu()

        if transcriptHistory.entries.isEmpty {
            menu.addItem(NSMenuItem(title: "Noch keine Transkripte", action: nil, keyEquivalent: ""))
        } else {
            for (label, transcript) in zip(transcriptHistory.displayItems, transcriptHistory.entries) {
                let item = NSMenuItem(
                    title: label,
                    action: #selector(copyTranscriptFromHistoryButton(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = transcript
                menu.addItem(item)
            }
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: historyButton.bounds.height + 4),
            in: historyButton
        )
    }

    @objc private func copyTranscriptFromHistoryButton(_ sender: NSMenuItem) {
        guard let transcript = sender.representedObject as? String else { return }
        onCopyHistoryTranscript(transcript)
    }

    @objc private func startKeyCapture() {
        captureMonitor.map(NSEvent.removeMonitor)
        captureMonitor = nil
        learnKeyButton.isEnabled = false
        setStatus("Drücke jetzt die gewünschte Sprechtaste …")

        let events: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .systemDefined
        ]
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            guard let self else { return event }
            if let key = self.learnedKey(from: event) {
                self.finishKeyCapture(with: key)
                return nil
            }
            return event
        }
    }

    private func finishKeyCapture(with key: PushToTalkKey) {
        captureMonitor.map(NSEvent.removeMonitor)
        captureMonitor = nil
        learnKeyButton.isEnabled = true
        setSelectedKey(key)
        onKeyChanged(key)
        setStatus("Gespeichert: \(key.title)")
    }

    private func learnedKey(from event: NSEvent) -> PushToTalkKey? {
        if event.type == .systemDefined,
           event.subtype.rawValue == 8,
           let mediaEvent = MediaKeyEvent(data1: event.data1),
           mediaEvent.isPressed {
            return .learnedMedia(
                keyCode: mediaEvent.keyCode,
                displayName: mediaKeyName(mediaEvent.keyCode)
            )
        }

        if event.type == .flagsChanged {
            guard isModifierKeyCode(event.keyCode) else { return nil }
            return .learned(
                keyCode: event.keyCode,
                displayName: modifierKeyName(event.keyCode),
                isModifier: true
            )
        }

        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let known = PushToTalkKey.allCases.first { $0.keyCode == event.keyCode }
        return .learned(
            keyCode: event.keyCode,
            displayName: known?.title ?? keyName(for: event),
            isModifier: false
        )
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    private func modifierKeyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 54:
            return "Rechte Befehlstaste (⌘)"
        case 55:
            return "Linke Befehlstaste (⌘)"
        case 56:
            return "Linke Umschalttaste (⇧)"
        case 57:
            return "Feststelltaste"
        case 58:
            return "Linke Wahltaste (⌥)"
        case 59:
            return "Linke Control-Taste (⌃)"
        case 60:
            return "Rechte Umschalttaste (⇧)"
        case 61:
            return "Rechte Wahltaste (⌥)"
        case 62:
            return "Rechte Control-Taste (⌃)"
        case 63:
            return "Fn/Globe"
        default:
            return "Taste \(keyCode)"
        }
    }

    private func keyName(for event: NSEvent) -> String {
        if event.keyCode == 49 { return "Leertaste" }
        if event.keyCode == 36 { return "Return" }
        if event.keyCode == 48 { return "Tab" }
        if event.keyCode == 51 { return "Backspace" }
        if event.keyCode == 53 { return "Escape" }
        if (122...126).contains(event.keyCode) || (96...111).contains(event.keyCode) {
            return "F-Taste \(event.keyCode)"
        }
        if let characters = event.charactersIgnoringModifiers,
           !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return characters.uppercased()
        }
        return "Taste \(event.keyCode)"
    }

    private func mediaKeyName(_ keyCode: Int) -> String {
        switch keyCode {
        case 16:
            return "Play/Pause"
        case 17:
            return "Nächster Titel"
        case 18:
            return "Vorheriger Titel"
        default:
            return "Medientaste \(keyCode)"
        }
    }

    private static func microphoneSelections() -> [MicrophoneSelection] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .microphone,
                .external
            ],
            mediaType: .audio,
            position: .unspecified
        ).devices

        let manual = devices.map {
            MicrophoneSelection.manual(deviceID: $0.uniqueID, name: $0.localizedName)
        }
        return [.systemDefault] + manual
    }

    @objc private func openPrivacySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let pushToTalkKeyDefaultsKey = "pushToTalkKey"
    private static let whisperModelDefaultsKey = "whisperModel"
    private static let microphoneSelectionDefaultsKey = "microphoneSelection"
    private static let transcriptHistoryDefaultsKey = "transcriptHistory"

    private enum TranscriptionDestination {
        case paste
        case test
    }

    private let recorder = AudioRecorder()
    private var hotkeyMonitor: PushToTalkMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var copyLatestMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var pushToTalkState = PushToTalkState()
    private var selectedKey = PushToTalkKey.defaultKey
    private var selectedModel = WhisperModel.defaultModel
    private var selectedMicrophone = MicrophoneSelection.systemDefault
    private var transcriptHistory = TranscriptHistory()
    private var isTestRecording = false
    private var isInstallingModel = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        selectedKey = PushToTalkKey(
            savedValue: UserDefaults.standard.string(
                forKey: Self.pushToTalkKeyDefaultsKey
            )
        )
        selectedModel = WhisperModel(
            savedValue: UserDefaults.standard.string(
                forKey: Self.whisperModelDefaultsKey
            )
        )
        selectedMicrophone = MicrophoneSelection(
            savedValue: UserDefaults.standard.string(
                forKey: Self.microphoneSelectionDefaultsKey
            )
        )
        transcriptHistory = TranscriptHistory(
            entries: UserDefaults.standard.stringArray(
                forKey: Self.transcriptHistoryDefaultsKey
            ) ?? []
        )
        configureStatusItem()
        TextInserter.promptForAccessibility()

        hotkeyMonitor = PushToTalkMonitor(
            key: selectedKey,
            onPress: { [weak self] in self?.beginRecording() },
            onRelease: { [weak self] in self?.finishRecording() }
        )
        hotkeyMonitor?.start()
        configureSettingsWindow()
        updateTranscriptHistoryViews()
        settingsWindowController?.show()
        refreshPermissions()
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshPermissions()
            settingsWindowController?.refreshMicrophones(selected: selectedMicrophone)
            await installSelectedModelIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        settingsWindowController?.show()
        return true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "mic",
            accessibilityDescription: "Local Flow"
        )

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: readyText, action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Einstellungen öffnen",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        copyLatestMenuItem = NSMenuItem(
            title: "Letzten Text kopieren",
            action: #selector(copyLatestTranscript),
            keyEquivalent: ""
        )
        copyLatestMenuItem.target = self
        menu.addItem(copyLatestMenuItem)

        historyMenu = NSMenu(title: "Transkript-Historie")
        let historyItem = NSMenuItem(title: "Transkript-Historie", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
        menu.addItem(
            withTitle: "Local Flow beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    private func configureSettingsWindow() {
        settingsWindowController = SettingsWindowController(
            selectedKey: selectedKey,
            selectedModel: selectedModel,
            selectedMicrophone: selectedMicrophone,
            onKeyChanged: { [weak self] key in
                self?.changePushToTalkKey(to: key)
            },
            onModelChanged: { [weak self] model in
                self?.changeWhisperModel(to: model)
            },
            onMicrophoneChanged: { [weak self] microphone in
                self?.changeMicrophone(to: microphone)
            },
            onTestRecording: { [weak self] in
                self?.beginTestRecording()
            },
            onCopyLatestTranscript: { [weak self] in
                self?.copyLatestTranscript()
            },
            onCopyHistoryTranscript: { [weak self] transcript in
                self?.copyTranscriptToPasteboard(transcript)
            }
        )
    }

    private func changePushToTalkKey(to key: PushToTalkKey) {
        selectedKey = key
        UserDefaults.standard.set(key.rawValue, forKey: Self.pushToTalkKeyDefaultsKey)
        hotkeyMonitor?.updateKey(key)
        settingsWindowController?.setSelectedKey(key)
        updateStatus(readyText, symbol: "mic")
    }

    private func changeWhisperModel(to model: WhisperModel) {
        selectedModel = model
        UserDefaults.standard.set(
            model.rawValue,
            forKey: Self.whisperModelDefaultsKey
        )
        Task {
            await installSelectedModelIfNeeded()
        }
    }

    private func changeMicrophone(to microphone: MicrophoneSelection) {
        selectedMicrophone = microphone
        UserDefaults.standard.set(
            microphone.rawValue,
            forKey: Self.microphoneSelectionDefaultsKey
        )
        updateStatus(readyText, symbol: "mic")
    }

    private func beginRecording() {
        guard !isTestRecording, !isInstallingModel else { return }
        guard ModelInstaller.isInstalled(selectedModel) else {
            Task { await installSelectedModelIfNeeded() }
            return
        }
        guard pushToTalkState.press() == .startRecording else { return }
        updateStatus("Aufnahme läuft …", symbol: "waveform.circle.fill")

        Task {
            do {
                try await recorder.start(microphone: selectedMicrophone)
                if pushToTalkState.recordingDidStart() == .stopRecording {
                    stopAndTranscribe(destination: .paste)
                }
            } catch {
                pushToTalkState.recordingDidFail()
                recorder.cancel()
                show(error)
            }
        }
    }

    private func finishRecording() {
        guard pushToTalkState.release() == .stopRecording else { return }
        stopAndTranscribe(destination: .paste)
    }

    private func beginTestRecording() {
        guard !isTestRecording, !isInstallingModel else { return }
        guard ModelInstaller.isInstalled(selectedModel) else {
            Task { await installSelectedModelIfNeeded() }
            return
        }
        isTestRecording = true
        settingsWindowController?.setTestRecordingEnabled(false)
        settingsWindowController?.setTestResult("Testaufnahme läuft …")
        updateStatus("Testaufnahme läuft …", symbol: "waveform.circle.fill")

        Task {
            do {
                try await recorder.start(microphone: selectedMicrophone)
                try await Task.sleep(for: .seconds(4))
                stopAndTranscribe(destination: .test)
            } catch {
                isTestRecording = false
                recorder.cancel()
                settingsWindowController?.setTestRecordingEnabled(true)
                show(error)
            }
        }
    }

    private func stopAndTranscribe(destination: TranscriptionDestination) {
        updateStatus(
            "Transkribiere mit \(selectedModel.title) …",
            symbol: "ellipsis.circle"
        )

        do {
            let audioURL = try recorder.stop()
            let model = selectedModel
            Task.detached {
                let result = Result {
                    try WhisperTranscriber.transcribe(
                        audioURL: audioURL,
                        model: model
                    )
                }
                await MainActor.run {
                    self.handleTranscription(result, destination: destination)
                }
            }
        } catch {
            finishProcessing(destination: destination)
            show(error)
        }
    }

    private func handleTranscription(
        _ result: Result<String, Error>,
        destination: TranscriptionDestination
    ) {
        finishProcessing(destination: destination)
        do {
            let transcript = try result.get()
            recordTranscript(transcript)

            switch destination {
            case .paste:
                try TextInserter.paste(transcript)
                updateStatus("Eingefügt", symbol: "checkmark.circle.fill")
            case .test:
                settingsWindowController?.setTestResult(transcript)
                updateStatus("Test fertig", symbol: "checkmark.circle.fill")
            }
            resetStatusSoon()
        } catch {
            show(error)
        }
    }

    private func finishProcessing(destination: TranscriptionDestination) {
        switch destination {
        case .paste:
            pushToTalkState.processingDidFinish()
        case .test:
            isTestRecording = false
            settingsWindowController?.setTestRecordingEnabled(true)
        }
    }

    private func recordTranscript(_ transcript: String) {
        transcriptHistory.record(transcript)
        UserDefaults.standard.set(
            transcriptHistory.entries,
            forKey: Self.transcriptHistoryDefaultsKey
        )
        updateTranscriptHistoryViews()
    }

    private func updateTranscriptHistoryViews() {
        let hasHistory = transcriptHistory.latest != nil
        copyLatestMenuItem?.isEnabled = hasHistory
        settingsWindowController?.setHasTranscriptHistory(hasHistory)
        settingsWindowController?.setTranscriptHistory(transcriptHistory)

        historyMenu?.removeAllItems()
        guard hasHistory else {
            historyMenu?.addItem(NSMenuItem(title: "Noch keine Transkripte", action: nil, keyEquivalent: ""))
            return
        }

        for (index, transcript) in transcriptHistory.entries.enumerated() {
            let item = NSMenuItem(
                title: "\(index + 1). \(transcript)",
                action: #selector(copyHistoryTranscript(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = transcript
            historyMenu?.addItem(item)
        }
    }

    @objc private func copyLatestTranscript() {
        guard let transcript = transcriptHistory.latest else { return }
        copyTranscriptToPasteboard(transcript)
    }

    @objc private func copyHistoryTranscript(_ sender: NSMenuItem) {
        guard let transcript = sender.representedObject as? String else { return }
        copyTranscriptToPasteboard(transcript)
    }

    private func copyTranscriptToPasteboard(_ transcript: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        settingsWindowController?.setTestResult("Kopiert: \(transcript)")
        updateStatus("Text kopiert", symbol: "doc.on.clipboard.fill")
        resetStatusSoon()
    }

    private func installSelectedModelIfNeeded() async {
        let model = selectedModel
        if ModelInstaller.isInstalled(model) {
            updateStatus(readyText, symbol: "mic")
            return
        }
        guard !isInstallingModel else { return }

        isInstallingModel = true
        settingsWindowController?.setTestRecordingEnabled(false)
        updateStatus(
            "Lade \(model.title) einmalig herunter …",
            symbol: "arrow.down.circle"
        )

        do {
            try await ModelInstaller.install(model)
            updateStatus("Sprachmodell ist bereit", symbol: "checkmark.circle.fill")
            resetStatusSoon()
        } catch {
            show(error)
        }

        isInstallingModel = false
        settingsWindowController?.setTestRecordingEnabled(true)

        if selectedModel != model {
            await installSelectedModelIfNeeded()
        }
    }

    private func show(_ error: Error) {
        NSSound.beep()
        updateStatus(
            error.localizedDescription,
            symbol: "exclamationmark.triangle.fill"
        )
        resetStatusSoon()
    }

    private func updateStatus(_ text: String, symbol: String) {
        statusMenuItem.title = text
        settingsWindowController?.setStatus(text)
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: text
        )
    }

    private func refreshPermissions() {
        settingsWindowController?.setPermissionsStatus(
            microphoneAllowed: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibilityAllowed: AXIsProcessTrusted()
        )
    }

    private func resetStatusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.updateStatus(self.readyText, symbol: "mic")
        }
    }

    private var readyText: String {
        "Bereit: \(selectedKey.title) · \(selectedModel.title)"
    }

    @objc private func openSettings() {
        refreshPermissions()
        settingsWindowController?.refreshMicrophones(selected: selectedMicrophone)
        settingsWindowController?.show()
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
