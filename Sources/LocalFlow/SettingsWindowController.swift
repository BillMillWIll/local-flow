import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

@MainActor
final class SettingsWindowController: NSWindowController {
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
