import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

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
        if let override = ProcessInfo.processInfo.environment[
            "LOCAL_FLOW_MODEL_DIRECTORY"
        ], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalFlow")
    }

    static func modelURL(for model: WhisperModel) -> URL {
        modelDirectory.appendingPathComponent(model.fileName)
    }

    static func isInstalled(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: model).path)
    }

    static func install(
        _ model: WhisperModel,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        if isInstalled(model) {
            return
        }

        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )

        let partialURL = modelURL(for: model).appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partialURL)

        do {
            try await ModelDownloadTask.download(
                from: model.downloadURL,
                to: partialURL,
                progress: progress
            )
        } catch {
            throw LocalFlowError.modelDownloadFailed
        }

        do {
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

private final class ModelDownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let progress: @Sendable (ModelDownloadProgress) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var lastReportedPercentage: Int?
    private var reportedUnknownProgress = false

    private init(
        destinationURL: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) {
        self.destinationURL = destinationURL
        self.progress = progress
    }

    static func download(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let delegate = ModelDownloadTask(
            destinationURL: destinationURL,
            progress: progress
        )
        try await delegate.start(sourceURL)
    }

    private func start(_ sourceURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = 3_600
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            self.session = session
            session.downloadTask(with: sourceURL).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : nil
        let currentProgress = ModelDownloadProgress(
            receivedBytes: totalBytesWritten,
            totalBytes: total
        )
        if let percentage = currentProgress.percentage {
            guard percentage != lastReportedPercentage else { return }
            lastReportedPercentage = percentage
        } else {
            guard !reportedUnknownProgress else { return }
            reportedUnknownProgress = true
        }
        progress(currentProgress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}

private struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private enum UpdateChecker {
    static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/BillMillWIll/local-flow/releases/latest"
    )!

    static func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Local-Flow", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
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
    private let statusSymbol = NSImageView()
    private let statusTitleLabel = NSTextField(labelWithString: "")
    private let statusDetailLabel = NSTextField(labelWithString: "")
    private let downloadProgress = NSProgressIndicator()
    private let retryDownloadButton = NSButton()
    private let updateButton = NSButton()
    private let microphonePermissionSymbol = NSImageView()
    private let microphonePermissionLabel = NSTextField(labelWithString: "Mikrofon")
    private let microphonePermissionButton = NSButton()
    private let accessibilityPermissionSymbol = NSImageView()
    private let accessibilityPermissionLabel = NSTextField(labelWithString: "Bedienungshilfen")
    private let accessibilityPermissionButton = NSButton()
    private let advancedButton = NSButton()
    private let advancedStack = NSStackView()
    private var captureMonitor: Any?
    private var updateURL: URL?
    private var isAdvancedVisible = false
    private let onKeyChanged: (PushToTalkKey) -> Void
    private let onModelChanged: (WhisperModel) -> Void
    private let onMicrophoneChanged: (MicrophoneSelection) -> Void
    private let onTestRecording: () -> Void
    private let onCopyLatestTranscript: () -> Void
    private let onCopyHistoryTranscript: (String) -> Void
    private let onRetryModelDownload: () -> Void
    private let onCheckForUpdates: () -> Void
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
        onCopyHistoryTranscript: @escaping (String) -> Void,
        onRetryModelDownload: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.onKeyChanged = onKeyChanged
        self.onModelChanged = onModelChanged
        self.onMicrophoneChanged = onMicrophoneChanged
        self.onTestRecording = onTestRecording
        self.onCopyLatestTranscript = onCopyLatestTranscript
        self.onCopyHistoryTranscript = onCopyHistoryTranscript
        self.onRetryModelDownload = onRetryModelDownload
        self.onCheckForUpdates = onCheckForUpdates

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
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
        statusDetailLabel.stringValue = text
    }

    func setActivity(_ activity: LocalFlowActivity) {
        statusTitleLabel.stringValue = activity.title
        statusDetailLabel.stringValue = activity.detail
        statusSymbol.image = NSImage(
            systemSymbolName: activity.symbolName,
            accessibilityDescription: activity.title
        )
        statusSymbol.contentTintColor = Self.color(for: activity.tone)
    }

    func setSelectedKey(_ key: PushToTalkKey) {
        keyValueLabel.stringValue = key.title
    }

    func setPermissionsStatus(microphoneAllowed: Bool, accessibilityAllowed: Bool) {
        Self.configurePermission(
            allowed: microphoneAllowed,
            symbol: microphonePermissionSymbol,
            label: microphonePermissionLabel,
            button: microphonePermissionButton
        )
        Self.configurePermission(
            allowed: accessibilityAllowed,
            symbol: accessibilityPermissionSymbol,
            label: accessibilityPermissionLabel,
            button: accessibilityPermissionButton
        )
    }

    func setTestResult(_ text: String) {
        resultLabel.stringValue = text
    }

    func setTestRecordingEnabled(_ enabled: Bool) {
        testButton.isEnabled = enabled
    }

    func setModelDownloadProgress(_ progress: ModelDownloadProgress?) {
        guard let progress else {
            downloadProgress.isHidden = true
            retryDownloadButton.isHidden = true
            return
        }

        downloadProgress.isHidden = false
        retryDownloadButton.isHidden = true
        if let percentage = progress.percentage {
            downloadProgress.isIndeterminate = false
            downloadProgress.doubleValue = Double(percentage)
        } else {
            downloadProgress.isIndeterminate = true
            downloadProgress.startAnimation(nil)
        }
    }

    func setModelDownloadFailed() {
        downloadProgress.stopAnimation(nil)
        downloadProgress.isHidden = true
        retryDownloadButton.isHidden = false
    }

    func setUpdateAvailable(version: String, url: URL) {
        updateButton.title = "Update \(version) laden"
        updateURL = url
        updateButton.isHidden = false
    }

    func setUpdateCheckResult(_ text: String) {
        updateButton.title = text
        updateURL = nil
        updateButton.isHidden = false
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

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: "Local Flow")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let subtitle = NSTextField(
            labelWithString: "Lokal sprechen. Direkt einfügen."
        )
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        statusSymbol.imageScaling = .scaleProportionallyUpOrDown
        statusTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusDetailLabel.font = .systemFont(ofSize: 12)
        statusDetailLabel.textColor = .secondaryLabelColor

        let statusText = NSStackView(views: [statusTitleLabel, statusDetailLabel])
        statusText.orientation = .vertical
        statusText.alignment = .leading
        statusText.spacing = 2

        let statusRow = NSStackView(views: [statusSymbol, statusText])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 12

        let statusSurface = NSView()
        statusSurface.wantsLayer = true
        statusSurface.layer?.cornerRadius = 12
        statusSurface.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusSurface.addSubview(statusRow)
        NSLayoutConstraint.activate([
            statusRow.leadingAnchor.constraint(equalTo: statusSurface.leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: statusSurface.trailingAnchor, constant: -16),
            statusRow.centerYAnchor.constraint(equalTo: statusSurface.centerYAnchor),
            statusSurface.heightAnchor.constraint(equalToConstant: 72),
            statusSymbol.widthAnchor.constraint(equalToConstant: 28),
            statusSymbol.heightAnchor.constraint(equalToConstant: 28)
        ])

        keyValueLabel.stringValue = selectedKey.title
        keyValueLabel.font = .systemFont(ofSize: 13, weight: .medium)

        learnKeyButton.title = "Ändern"
        learnKeyButton.target = self
        learnKeyButton.action = #selector(startKeyCapture)
        learnKeyButton.bezelStyle = .rounded

        modelPopup.addItems(withTitles: WhisperModel.allCases.map(\.title))
        modelPopup.selectItem(
            at: WhisperModel.allCases.firstIndex(of: selectedModel) ?? 0
        )
        modelPopup.target = self
        modelPopup.action = #selector(modelSelectionChanged)

        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneSelectionChanged)
        refreshMicrophones(selected: selectedMicrophone)

        testButton.title = "Aufnahme testen"
        testButton.target = self
        testButton.action = #selector(testRecording)
        testButton.bezelStyle = .rounded
        testButton.keyEquivalent = "\r"
        testButton.contentTintColor = .systemMint
        testButton.bezelColor = .systemMint

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
        resultLabel.maximumNumberOfLines = 3

        downloadProgress.minValue = 0
        downloadProgress.maxValue = 100
        downloadProgress.controlSize = .small
        downloadProgress.style = .bar
        downloadProgress.isHidden = true

        retryDownloadButton.title = "Download erneut versuchen"
        retryDownloadButton.target = self
        retryDownloadButton.action = #selector(retryModelDownload)
        retryDownloadButton.bezelStyle = .rounded
        retryDownloadButton.isHidden = true

        updateButton.title = "Nach Updates suchen"
        updateButton.target = self
        updateButton.action = #selector(checkForUpdates)
        updateButton.bezelStyle = .rounded

        microphonePermissionButton.title = "Öffnen"
        microphonePermissionButton.target = self
        microphonePermissionButton.action = #selector(openMicrophoneSettings)
        microphonePermissionButton.bezelStyle = .rounded

        accessibilityPermissionButton.title = "Öffnen"
        accessibilityPermissionButton.target = self
        accessibilityPermissionButton.action = #selector(openPrivacySettings)
        accessibilityPermissionButton.bezelStyle = .rounded

        let microphonePermissionRow = permissionRow(
            symbol: microphonePermissionSymbol,
            label: microphonePermissionLabel,
            button: microphonePermissionButton
        )
        let accessibilityPermissionRow = permissionRow(
            symbol: accessibilityPermissionSymbol,
            label: accessibilityPermissionLabel,
            button: accessibilityPermissionButton
        )

        let keyRow = NSStackView(views: [keyValueLabel, learnKeyButton])
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 12

        let testRow = NSStackView(views: [testButton, resultLabel])
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 14

        let advancedActionRow = NSStackView(views: [copyLatestButton, historyButton, updateButton])
        advancedActionRow.orientation = .horizontal
        advancedActionRow.spacing = 10

        advancedStack.orientation = .vertical
        advancedStack.alignment = .leading
        advancedStack.spacing = 10
        advancedStack.addArrangedSubview(advancedActionRow)
        advancedStack.isHidden = true

        advancedButton.title = "Erweiterte Einstellungen anzeigen"
        advancedButton.target = self
        advancedButton.action = #selector(toggleAdvancedSettings)
        advancedButton.bezelStyle = .inline
        advancedButton.font = .systemFont(ofSize: 13, weight: .medium)
        advancedButton.contentTintColor = .secondaryLabelColor
        advancedButton.imagePosition = .imageLeading
        advancedButton.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )

        let speakingSection = NSStackView(views: [
            settingRow(label: "Sprechtaste", control: keyRow),
            settingRow(label: "Mikrofon", control: microphonePopup),
            settingRow(label: "Sprachmodell", control: modelPopup)
        ])
        speakingSection.orientation = .vertical
        speakingSection.alignment = .leading
        speakingSection.spacing = 10

        let permissionsSection = NSStackView(views: [
            microphonePermissionRow,
            accessibilityPermissionRow
        ])
        permissionsSection.orientation = .vertical
        permissionsSection.alignment = .leading
        permissionsSection.spacing = 8

        let stack = NSStackView(views: [
            header,
            statusSurface,
            sectionLabel("SPRECHEN"),
            speakingSection,
            divider(),
            sectionLabel("TEST"),
            testRow,
            downloadProgress,
            retryDownloadButton,
            divider(),
            sectionLabel("BERECHTIGUNGEN"),
            permissionsSection,
            advancedButton,
            advancedStack
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
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusSurface.widthAnchor.constraint(equalTo: stack.widthAnchor),
            speakingSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            testRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionsSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            keyValueLabel.widthAnchor.constraint(equalToConstant: 250),
            modelPopup.widthAnchor.constraint(equalToConstant: 330),
            microphonePopup.widthAnchor.constraint(equalToConstant: 330),
            downloadProgress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resultLabel.widthAnchor.constraint(equalToConstant: 330)
        ])

        setActivity(.ready(keyTitle: selectedKey.title))
        setPermissionsStatus(microphoneAllowed: false, accessibilityAllowed: false)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func divider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        return divider
    }

    private func settingRow(label title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func permissionRow(
        symbol: NSImageView,
        label: NSTextField,
        button: NSButton
    ) -> NSStackView {
        symbol.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 360).isActive = true
        symbol.widthAnchor.constraint(equalToConstant: 18).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let row = NSStackView(views: [symbol, label, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private static func configurePermission(
        allowed: Bool,
        symbol: NSImageView,
        label: NSTextField,
        button: NSButton
    ) {
        symbol.image = NSImage(
            systemSymbolName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            accessibilityDescription: nil
        )
        symbol.contentTintColor = allowed ? .systemGreen : .systemOrange
        label.textColor = allowed ? .labelColor : .secondaryLabelColor
        button.isHidden = allowed
    }

    private static func color(for tone: ActivityTone) -> NSColor {
        switch tone {
        case .neutral:
            return .secondaryLabelColor
        case .accent:
            return .systemMint
        case .recording:
            return .systemRed
        case .success:
            return .systemGreen
        case .warning:
            return .systemOrange
        }
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

    @objc private func retryModelDownload() {
        onRetryModelDownload()
    }

    @objc private func checkForUpdates() {
        if let url = updateURL {
            NSWorkspace.shared.open(url)
        } else {
            onCheckForUpdates()
        }
    }

    @objc private func toggleAdvancedSettings() {
        isAdvancedVisible.toggle()
        advancedStack.isHidden = !isAdvancedVisible
        advancedButton.title = isAdvancedVisible
            ? "Erweiterte Einstellungen ausblenden"
            : "Erweiterte Einstellungen anzeigen"
        advancedButton.image = NSImage(
            systemSymbolName: isAdvancedVisible ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )

        guard let window else { return }
        var frame = window.frame
        let heightChange: CGFloat = isAdvancedVisible ? 64 : -64
        frame.origin.y -= heightChange
        frame.size.height += heightChange
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().setFrame(frame, display: true)
        }
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

    @objc private func openMicrophoneSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )!
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class OnboardingWindowController: NSWindowController {
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let microphoneSymbol = NSImageView()
    private let microphoneDetail = NSTextField(labelWithString: "Mikrofonzugriff erlauben")
    private let microphoneButton = NSButton()
    private let accessibilitySymbol = NSImageView()
    private let accessibilityDetail = NSTextField(labelWithString: "Bedienungshilfen erlauben")
    private let accessibilityButton = NSButton()
    private let modelSymbol = NSImageView()
    private let modelDetail = NSTextField(labelWithString: "Sprachmodell herunterladen")
    private let modelButton = NSButton()
    private let testSymbol = NSImageView()
    private let testDetail = NSTextField(labelWithString: "Kurze Testaufnahme durchführen")
    private let testButton = NSButton()
    private let finishButton = NSButton()
    private let onRequestMicrophone: () -> Void
    private let onRequestAccessibility: () -> Void
    private let onInstallModel: () -> Void
    private let onTestRecording: () -> Void
    private let onFinish: () -> Void
    private let onSkip: () -> Void

    init(
        onRequestMicrophone: @escaping () -> Void,
        onRequestAccessibility: @escaping () -> Void,
        onInstallModel: @escaping () -> Void,
        onTestRecording: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.onRequestMicrophone = onRequestMicrophone
        self.onRequestAccessibility = onRequestAccessibility
        self.onInstallModel = onInstallModel
        self.onTestRecording = onTestRecording
        self.onFinish = onFinish
        self.onSkip = onSkip

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Local Flow einrichten"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        configureContent()
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

    func setProgress(_ progress: OnboardingProgress) {
        progressIndicator.doubleValue = Double(progress.completedStepCount)
        progressLabel.stringValue = "\(progress.completedStepCount) von 4 Schritten abgeschlossen"

        configureStep(
            completed: progress.microphoneAllowed,
            symbol: microphoneSymbol,
            detail: microphoneDetail,
            button: microphoneButton,
            completedText: "Mikrofon ist bereit"
        )
        configureStep(
            completed: progress.accessibilityAllowed,
            symbol: accessibilitySymbol,
            detail: accessibilityDetail,
            button: accessibilityButton,
            completedText: "Bedienungshilfen sind bereit"
        )
        configureStep(
            completed: progress.modelInstalled,
            symbol: modelSymbol,
            detail: modelDetail,
            button: modelButton,
            completedText: "Sprachmodell ist bereit"
        )
        configureStep(
            completed: progress.testRecordingCompleted,
            symbol: testSymbol,
            detail: testDetail,
            button: testButton,
            completedText: "Testaufnahme abgeschlossen"
        )

        testButton.isEnabled = progress.microphoneAllowed && progress.modelInstalled
        finishButton.isEnabled = progress.canFinish
    }

    func setModelProgress(_ progress: ModelDownloadProgress?) {
        guard let progress else { return }
        modelDetail.stringValue = progress.percentage.map {
            "Sprachmodell wird geladen · \($0) %"
        } ?? "Sprachmodell wird geladen"
        modelButton.isEnabled = false
    }

    func setTestRunning(_ running: Bool) {
        testButton.isEnabled = !running
        testDetail.stringValue = running
            ? "Testaufnahme läuft …"
            : "Kurze Testaufnahme durchführen"
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: "Local Flow einrichten")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(
            wrappingLabelWithString: "Vier kurze Schritte, danach läuft die Spracheingabe vollständig lokal auf diesem Mac."
        )
        subtitle.textColor = .secondaryLabelColor

        progressIndicator.minValue = 0
        progressIndicator.maxValue = 4
        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = .secondaryLabelColor

        microphoneButton.title = "Erlauben"
        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophone)
        microphoneButton.bezelStyle = .rounded

        accessibilityButton.title = "Öffnen"
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility)
        accessibilityButton.bezelStyle = .rounded

        modelButton.title = "Herunterladen"
        modelButton.target = self
        modelButton.action = #selector(installModel)
        modelButton.bezelStyle = .rounded

        testButton.title = "Testen"
        testButton.target = self
        testButton.action = #selector(runTestRecording)
        testButton.bezelStyle = .rounded

        let steps = NSStackView(views: [
            stepRow(number: 1, symbol: microphoneSymbol, detail: microphoneDetail, button: microphoneButton),
            stepRow(number: 2, symbol: accessibilitySymbol, detail: accessibilityDetail, button: accessibilityButton),
            stepRow(number: 3, symbol: modelSymbol, detail: modelDetail, button: modelButton),
            stepRow(number: 4, symbol: testSymbol, detail: testDetail, button: testButton)
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 14

        finishButton.title = "Local Flow verwenden"
        finishButton.target = self
        finishButton.action = #selector(finish)
        finishButton.bezelStyle = .rounded
        finishButton.keyEquivalent = "\r"
        finishButton.contentTintColor = .systemMint
        finishButton.bezelColor = .systemMint
        finishButton.isEnabled = false

        let skipButton = NSButton(
            title: "Später einrichten",
            target: self,
            action: #selector(skip)
        )
        skipButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [skipButton, finishButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            icon,
            title,
            subtitle,
            progressIndicator,
            progressLabel,
            steps,
            buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            steps.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        setProgress(OnboardingProgress())
    }

    private func stepRow(
        number: Int,
        symbol: NSImageView,
        detail: NSTextField,
        button: NSButton
    ) -> NSStackView {
        let numberLabel = NSTextField(labelWithString: "\(number)")
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        numberLabel.alignment = .center
        numberLabel.textColor = .secondaryLabelColor
        numberLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true

        symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.widthAnchor.constraint(equalToConstant: 20).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 20).isActive = true
        detail.font = .systemFont(ofSize: 13, weight: .medium)
        detail.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let row = NSStackView(views: [numberLabel, symbol, detail, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func configureStep(
        completed: Bool,
        symbol: NSImageView,
        detail: NSTextField,
        button: NSButton,
        completedText: String
    ) {
        symbol.image = NSImage(
            systemSymbolName: completed ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: nil
        )
        symbol.contentTintColor = completed ? .systemGreen : .tertiaryLabelColor
        if completed {
            detail.stringValue = completedText
        }
        button.isHidden = completed
        button.isEnabled = true
    }

    @objc private func requestMicrophone() {
        onRequestMicrophone()
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility()
    }

    @objc private func installModel() {
        onInstallModel()
    }

    @objc private func runTestRecording() {
        onTestRecording()
    }

    @objc private func finish() {
        onFinish()
    }

    @objc private func skip() {
        onSkip()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let pushToTalkKeyDefaultsKey = "pushToTalkKey"
    private static let whisperModelDefaultsKey = "whisperModel"
    private static let microphoneSelectionDefaultsKey = "microphoneSelection"
    private static let transcriptHistoryDefaultsKey = "transcriptHistory"
    private static let onboardingCompletedDefaultsKey = "onboardingCompleted"

    private enum TranscriptionDestination {
        case paste
        case test
    }

    private let recorder = AudioRecorder()
    private var hotkeyMonitor: PushToTalkMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var copyLatestMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var pushToTalkState = PushToTalkState()
    private var selectedKey = PushToTalkKey.defaultKey
    private var selectedModel = WhisperModel.defaultModel
    private var selectedMicrophone = MicrophoneSelection.systemDefault
    private var transcriptHistory = TranscriptHistory()
    private var isTestRecording = false
    private var isInstallingModel = false
    private var onboardingTestCompleted = false

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

        hotkeyMonitor = PushToTalkMonitor(
            key: selectedKey,
            onPress: { [weak self] in self?.beginRecording() },
            onRelease: { [weak self] in self?.finishRecording() }
        )
        hotkeyMonitor?.start()
        configureSettingsWindow()
        configureOnboardingWindow()
        updateTranscriptHistoryViews()
        refreshPermissions()
        refreshOnboarding()

        if UserDefaults.standard.bool(forKey: Self.onboardingCompletedDefaultsKey) {
            settingsWindowController?.show()
        } else {
            onboardingWindowController?.show()
        }

        Task {
            settingsWindowController?.refreshMicrophones(selected: selectedMicrophone)
            await installSelectedModelIfNeeded()
            await checkForUpdates(showCurrentResult: false)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissions()
        refreshOnboarding()
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
        updateMenuItem = NSMenuItem(
            title: "Nach Updates suchen",
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)
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
            },
            onRetryModelDownload: { [weak self] in
                Task { await self?.installSelectedModelIfNeeded() }
            },
            onCheckForUpdates: { [weak self] in
                Task { await self?.checkForUpdates(showCurrentResult: true) }
            }
        )
    }

    private func configureOnboardingWindow() {
        onboardingWindowController = OnboardingWindowController(
            onRequestMicrophone: { [weak self] in
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    await MainActor.run {
                        self?.refreshPermissions()
                        self?.refreshOnboarding()
                        self?.settingsWindowController?.refreshMicrophones(
                            selected: self?.selectedMicrophone ?? .systemDefault
                        )
                    }
                }
            },
            onRequestAccessibility: { [weak self] in
                TextInserter.promptForAccessibility()
                self?.openAccessibilitySettings()
            },
            onInstallModel: { [weak self] in
                Task { await self?.installSelectedModelIfNeeded() }
            },
            onTestRecording: { [weak self] in
                self?.beginTestRecording()
            },
            onFinish: { [weak self] in
                UserDefaults.standard.set(
                    true,
                    forKey: Self.onboardingCompletedDefaultsKey
                )
                self?.onboardingWindowController?.close()
                self?.settingsWindowController?.show()
            },
            onSkip: { [weak self] in
                self?.onboardingWindowController?.close()
                self?.settingsWindowController?.show()
            }
        )
    }

    private func currentOnboardingProgress() -> OnboardingProgress {
        OnboardingProgress(
            microphoneAllowed: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibilityAllowed: AXIsProcessTrusted(),
            modelInstalled: ModelInstaller.isInstalled(selectedModel),
            testRecordingCompleted: onboardingTestCompleted
        )
    }

    private func refreshOnboarding() {
        onboardingWindowController?.setProgress(currentOnboardingProgress())
    }

    private func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
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
        onboardingWindowController?.setTestRunning(true)
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
                onboardingWindowController?.setTestRunning(false)
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
                onboardingTestCompleted = true
                refreshOnboarding()
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
            onboardingWindowController?.setTestRunning(false)
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
        settingsWindowController?.setModelDownloadProgress(
            ModelDownloadProgress(receivedBytes: 0, totalBytes: nil)
        )
        onboardingWindowController?.setModelProgress(
            ModelDownloadProgress(receivedBytes: 0, totalBytes: nil)
        )
        updateStatus(
            "Lade \(model.title) einmalig herunter …",
            symbol: "arrow.down.circle"
        )

        do {
            try await ModelInstaller.install(model) { [weak self] progress in
                Task { @MainActor in
                    self?.settingsWindowController?.setModelDownloadProgress(progress)
                    self?.onboardingWindowController?.setModelProgress(progress)
                    if let percentage = progress.percentage {
                        self?.updateStatus(
                            "Lade \(model.title): \(percentage) %",
                            symbol: "arrow.down.circle"
                        )
                    }
                }
            }
            settingsWindowController?.setModelDownloadProgress(nil)
            refreshOnboarding()
            updateStatus("Sprachmodell ist bereit", symbol: "checkmark.circle.fill")
            resetStatusSoon()
        } catch {
            settingsWindowController?.setModelDownloadFailed()
            refreshOnboarding()
            show(error)
        }

        isInstallingModel = false
        settingsWindowController?.setTestRecordingEnabled(true)
        refreshOnboarding()

        if selectedModel != model {
            await installSelectedModelIfNeeded()
        }
    }

    private func checkForUpdates(showCurrentResult: Bool) async {
        do {
            let release = try await UpdateChecker.latestRelease()
            let currentVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.0.0"
            let decision = UpdateDecision(
                current: currentVersion,
                latestTag: release.tagName
            )

            if decision.isUpdateAvailable {
                let version = release.tagName.hasPrefix("v")
                    ? String(release.tagName.dropFirst())
                    : release.tagName
                settingsWindowController?.setUpdateAvailable(
                    version: version,
                    url: release.htmlURL
                )
                updateMenuItem.title = "Update \(version) laden"
                updateMenuItem.representedObject = release.htmlURL
            } else if showCurrentResult {
                settingsWindowController?.setUpdateCheckResult("App ist aktuell")
                updateStatus("Local Flow ist aktuell", symbol: "checkmark.circle")
                resetStatusSoon()
            }
        } catch {
            if showCurrentResult {
                settingsWindowController?.setUpdateCheckResult("Update-Prüfung wiederholen")
                updateStatus(
                    "Update-Prüfung fehlgeschlagen",
                    symbol: "exclamationmark.triangle"
                )
                resetStatusSoon()
            }
        }
    }

    @objc private func checkForUpdatesFromMenu(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        } else {
            Task { await checkForUpdates(showCurrentResult: true) }
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
        let activity: LocalFlowActivity
        switch symbol {
        case "waveform.circle.fill":
            activity = text.hasPrefix("Test") ? .testRecording : .recording
        case "ellipsis.circle":
            activity = .processing
        case "arrow.down.circle":
            let percentage = text
                .split(separator: " ")
                .compactMap { Int($0) }
                .last
            activity = .downloadingModel(percentage)
        case let value where value.contains("checkmark"):
            activity = .success(text)
        case let value where value.contains("exclamationmark"):
            activity = .failure(text)
        default:
            activity = .ready(keyTitle: selectedKey.title)
        }

        statusMenuItem.title = text
        settingsWindowController?.setActivity(activity)
        statusItem.button?.image = NSImage(
            systemSymbolName: activity.symbolName,
            accessibilityDescription: activity.title
        )
        statusItem.button?.contentTintColor = statusColor(for: activity.tone)
        updateStatusItemPulse(activity.isPulsing)
    }

    private func statusColor(for tone: ActivityTone) -> NSColor {
        switch tone {
        case .neutral:
            return .labelColor
        case .accent:
            return .systemMint
        case .recording:
            return .systemRed
        case .success:
            return .systemGreen
        case .warning:
            return .systemOrange
        }
    }

    private func updateStatusItemPulse(_ pulsing: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.layer?.removeAnimation(forKey: "localFlowPulse")
        button.layer?.opacity = 1
        guard pulsing else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.35
        animation.duration = 0.55
        animation.autoreverses = true
        animation.repeatCount = .infinity
        button.layer?.add(animation, forKey: "localFlowPulse")
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

private func runModelDownloadDiagnostic(model: WhisperModel) -> Never {
    Task {
        do {
            try await ModelInstaller.install(model) { progress in
                if let percentage = progress.percentage {
                    print("Download: \(percentage) %")
                }
            }
            print("Modell geprüft: \(ModelInstaller.modelURL(for: model).path)")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
}

let app = NSApplication.shared
if let argumentIndex = CommandLine.arguments.firstIndex(of: "--download-model"),
   CommandLine.arguments.indices.contains(argumentIndex + 1),
   let model = WhisperModel(
       rawValue: CommandLine.arguments[argumentIndex + 1]
   ) {
    runModelDownloadDiagnostic(model: model)
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
