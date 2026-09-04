import AppKit
import AVFoundation
import LocalFlowCore

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSTextViewDelegate {
    struct Callbacks {
        var onKeyChanged: (PushToTalkKey) -> Void
        var onEngineChanged: (RecognitionEngine) -> Void
        var onMicrophoneChanged: (MicrophoneSelection) -> Void
        var onCustomWordsChanged: (String) -> Void
        var onReplacementRulesChanged: (String) -> Void
        var onCleanupChanged: (Bool) -> Void
        var onSoundsChanged: (Bool) -> Void
        var onLoginItemChanged: (Bool) -> Void
        var onTestRecording: () -> Void
        var onCopyLatestTranscript: () -> Void
        var onCopyHistoryTranscript: (String) -> Void
        var onRetryModelDownload: () -> Void
        var onCheckForUpdates: () -> Void
    }

    struct InitialState {
        var selectedKey: PushToTalkKey
        var selectedEngine: RecognitionEngine
        var availableEngines: [RecognitionEngine]
        var selectedMicrophone: MicrophoneSelection
        var customWords: String
        var replacementRules: String
        var cleanupEnabled: Bool
        var cleanupAvailability: TextCleanup.Availability
        var soundsEnabled: Bool
        var loginItemEnabled: Bool
    }

    private let keyValueLabel = NSTextField(labelWithString: "")
    private let learnKeyButton = NSButton()
    private let enginePopup = NSPopUpButton()
    private let engineDetailLabel = NSTextField(wrappingLabelWithString: "")
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
    private let cleanupCheckbox = NSButton(checkboxWithTitle: "Mit Apple Intelligence bereinigen", target: nil, action: nil)
    private let cleanupDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let customWordsField = NSTextField()
    private let replacementRulesView = NSTextView()
    private let soundsCheckbox = NSButton(checkboxWithTitle: "Ton bei Start und Stopp der Aufnahme", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Local Flow beim Anmelden starten", target: nil, action: nil)
    private var captureMonitor: Any?
    private var updateURL: URL?
    private let callbacks: Callbacks
    private var availableEngines: [RecognitionEngine]
    private var availableMicrophones: [MicrophoneSelection] = []
    private var transcriptHistory = TranscriptHistory()

    init(state: InitialState, callbacks: Callbacks) {
        self.callbacks = callbacks
        self.availableEngines = state.availableEngines

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Local Flow"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        configureContent(state: state)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State updates

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

    func setSelectedEngine(_ engine: RecognitionEngine) {
        if let index = availableEngines.firstIndex(of: engine) {
            enginePopup.selectItem(at: index)
        }
        engineDetailLabel.stringValue = engine.detail
    }

    func setEngineDetail(_ text: String) {
        engineDetailLabel.stringValue = text
    }

    func setCleanupEnabled(_ enabled: Bool) {
        cleanupCheckbox.state = enabled ? .on : .off
    }

    func setCleanupAvailability(_ availability: TextCleanup.Availability) {
        cleanupCheckbox.isEnabled = availability.isAvailable
        cleanupDetailLabel.stringValue = availability.detail
        if !availability.isAvailable {
            cleanupCheckbox.state = .off
        }
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        loginCheckbox.state = enabled ? .on : .off
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
            downloadProgress.stopAnimation(nil)
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

    // MARK: - Layout

    private func configureContent(state: InitialState) {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: "Local Flow")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let subtitle = NSTextField(labelWithString: "Lokal sprechen. Direkt einfügen.")
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let statusSurface = makeStatusSurface()

        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.addTabViewItem(tabItem(title: "Sprechen", view: makeSpeakingTab(state: state)))
        tabView.addTabViewItem(tabItem(title: "Text", view: makeTextTab(state: state)))
        tabView.addTabViewItem(tabItem(title: "Erweitert", view: makeAdvancedTab(state: state)))

        let stack = NSStackView(views: [header, statusSurface, tabView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusSurface.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tabView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])

        setActivity(.ready(keyTitle: state.selectedKey.title))
        setPermissionsStatus(microphoneAllowed: false, accessibilityAllowed: false)
        setCleanupAvailability(state.cleanupAvailability)
        setCleanupEnabled(state.cleanupEnabled && state.cleanupAvailability.isAvailable)
    }

    private func makeStatusSurface() -> NSView {
        statusSymbol.imageScaling = .scaleProportionallyUpOrDown
        statusTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusDetailLabel.font = .systemFont(ofSize: 12)
        statusDetailLabel.textColor = .secondaryLabelColor
        statusDetailLabel.lineBreakMode = .byTruncatingTail

        let statusText = NSStackView(views: [statusTitleLabel, statusDetailLabel])
        statusText.orientation = .vertical
        statusText.alignment = .leading
        statusText.spacing = 2

        let statusRow = NSStackView(views: [statusSymbol, statusText])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 12

        let surface = NSView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 12
        surface.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(statusRow)
        NSLayoutConstraint.activate([
            statusRow.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            statusRow.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            surface.heightAnchor.constraint(equalToConstant: 72),
            statusSymbol.widthAnchor.constraint(equalToConstant: 28),
            statusSymbol.heightAnchor.constraint(equalToConstant: 28)
        ])
        return surface
    }

    private func makeSpeakingTab(state: InitialState) -> NSView {
        keyValueLabel.stringValue = state.selectedKey.title
        keyValueLabel.font = .systemFont(ofSize: 13, weight: .medium)

        learnKeyButton.title = "Ändern"
        learnKeyButton.target = self
        learnKeyButton.action = #selector(startKeyCapture)
        learnKeyButton.bezelStyle = .rounded

        let keyRow = NSStackView(views: [keyValueLabel, learnKeyButton])
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 12

        let keyHint = hintLabel(
            "Halten und sprechen. Zweimal kurz tippen für freihändiges Diktat, erneut tippen zum Einfügen. Esc bricht ab."
        )

        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneSelectionChanged)
        refreshMicrophones(selected: state.selectedMicrophone)

        enginePopup.addItems(withTitles: availableEngines.map(\.title))
        enginePopup.target = self
        enginePopup.action = #selector(engineSelectionChanged)
        setSelectedEngine(state.selectedEngine)
        engineDetailLabel.font = .systemFont(ofSize: 11)
        engineDetailLabel.textColor = .secondaryLabelColor

        testButton.title = "Aufnahme testen"
        testButton.target = self
        testButton.action = #selector(testRecording)
        testButton.bezelStyle = .rounded
        testButton.keyEquivalent = "\r"
        testButton.contentTintColor = .systemMint
        testButton.bezelColor = .systemMint

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

        microphonePermissionButton.title = "Öffnen"
        microphonePermissionButton.target = self
        microphonePermissionButton.action = #selector(openMicrophoneSettings)
        microphonePermissionButton.bezelStyle = .rounded

        accessibilityPermissionButton.title = "Öffnen"
        accessibilityPermissionButton.target = self
        accessibilityPermissionButton.action = #selector(openPrivacySettings)
        accessibilityPermissionButton.bezelStyle = .rounded

        let testRow = NSStackView(views: [testButton, resultLabel])
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 14

        let permissionsSection = NSStackView(views: [
            permissionRow(symbol: microphonePermissionSymbol, label: microphonePermissionLabel, button: microphonePermissionButton),
            permissionRow(symbol: accessibilityPermissionSymbol, label: accessibilityPermissionLabel, button: accessibilityPermissionButton)
        ])
        permissionsSection.orientation = .vertical
        permissionsSection.alignment = .leading
        permissionsSection.spacing = 8

        let stack = tabStack([
            settingRow(label: "Sprechtaste", control: keyRow),
            indented(keyHint),
            settingRow(label: "Mikrofon", control: microphonePopup),
            settingRow(label: "Erkennung", control: enginePopup),
            indented(engineDetailLabel),
            downloadProgress,
            retryDownloadButton,
            divider(),
            sectionLabel("TEST"),
            testRow,
            divider(),
            sectionLabel("BERECHTIGUNGEN"),
            permissionsSection
        ])
        NSLayoutConstraint.activate([
            keyValueLabel.widthAnchor.constraint(equalToConstant: 250),
            enginePopup.widthAnchor.constraint(equalToConstant: 360),
            microphonePopup.widthAnchor.constraint(equalToConstant: 360),
            resultLabel.widthAnchor.constraint(equalToConstant: 340),
            downloadProgress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            testRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionsSection.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return stack
    }

    private func makeTextTab(state: InitialState) -> NSView {
        cleanupCheckbox.target = self
        cleanupCheckbox.action = #selector(cleanupChanged)
        cleanupDetailLabel.font = .systemFont(ofSize: 11)
        cleanupDetailLabel.textColor = .secondaryLabelColor

        customWordsField.stringValue = state.customWords
        customWordsField.placeholderString = "Cuban, Moissanite, BABA"
        customWordsField.delegate = self
        customWordsField.font = .systemFont(ofSize: 13)
        let wordsHint = hintLabel(
            "Namen und Fachwörter, durch Kommas getrennt. Whisper Turbo lernt die Schreibweise direkt."
        )

        replacementRulesView.string = state.replacementRules
        replacementRulesView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        replacementRulesView.isRichText = false
        replacementRulesView.isAutomaticQuoteSubstitutionEnabled = false
        replacementRulesView.isAutomaticDashSubstitutionEnabled = false
        replacementRulesView.isAutomaticTextReplacementEnabled = false
        replacementRulesView.delegate = self
        replacementRulesView.textContainerInset = NSSize(width: 6, height: 6)
        replacementRulesView.isVerticallyResizable = true
        replacementRulesView.autoresizingMask = [.width]
        replacementRulesView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = replacementRulesView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let rulesHint = hintLabel(
            "Eine Regel je Zeile: gehört = gewünscht. Gilt für jede Erkennung. \\n steht für einen Zeilenumbruch."
        )

        let stack = tabStack([
            sectionLabel("BEREINIGEN"),
            cleanupCheckbox,
            cleanupDetailLabel,
            divider(),
            sectionLabel("EIGENE WÖRTER"),
            customWordsField,
            wordsHint,
            divider(),
            sectionLabel("ERSETZUNGEN"),
            scrollView,
            rulesHint
        ])
        NSLayoutConstraint.activate([
            cleanupDetailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            customWordsField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            wordsHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 96),
            rulesHint.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return stack
    }

    private func makeAdvancedTab(state: InitialState) -> NSView {
        soundsCheckbox.target = self
        soundsCheckbox.action = #selector(soundsChanged)
        soundsCheckbox.state = state.soundsEnabled ? .on : .off

        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginItemChanged)
        loginCheckbox.state = state.loginItemEnabled ? .on : .off

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

        updateButton.title = "Nach Updates suchen"
        updateButton.target = self
        updateButton.action = #selector(checkForUpdates)
        updateButton.bezelStyle = .rounded

        let actionRow = NSStackView(views: [copyLatestButton, historyButton, updateButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10

        let privacy = hintLabel(
            "Aufnahmen werden nach dem Diktat gelöscht. Es verlässt nichts diesen Mac, außer der einmalige Modell-Download und die Update-Prüfung."
        )

        let stack = tabStack([
            sectionLabel("VERHALTEN"),
            soundsCheckbox,
            loginCheckbox,
            divider(),
            sectionLabel("TEXTE UND UPDATES"),
            actionRow,
            divider(),
            sectionLabel("DATENSCHUTZ"),
            privacy
        ])
        NSLayoutConstraint.activate([
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return stack
    }

    // MARK: - Helpers

    private func tabItem(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
        item.view = container
        return item
    }

    private func tabStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for view in views where view is NSBox || view is NSStackView && (view as? NSStackView)?.orientation == .vertical {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func hintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 480
        return label
    }

    private func indented(_ view: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [spacer, view])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14
        if let field = view as? NSTextField {
            field.preferredMaxLayoutWidth = 380
        }
        return row
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

    private func permissionRow(symbol: NSImageView, label: NSTextField, button: NSButton) -> NSStackView {
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

    private static func configurePermission(allowed: Bool, symbol: NSImageView, label: NSTextField, button: NSButton) {
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

    // MARK: - Actions

    @objc private func engineSelectionChanged() {
        guard availableEngines.indices.contains(enginePopup.indexOfSelectedItem) else { return }
        let engine = availableEngines[enginePopup.indexOfSelectedItem]
        engineDetailLabel.stringValue = engine.detail
        callbacks.onEngineChanged(engine)
        setStatus("Erkennung gespeichert: \(engine.shortTitle)")
    }

    @objc private func microphoneSelectionChanged() {
        guard availableMicrophones.indices.contains(microphonePopup.indexOfSelectedItem) else { return }
        let microphone = availableMicrophones[microphonePopup.indexOfSelectedItem]
        callbacks.onMicrophoneChanged(microphone)
        setStatus("Mikrofon gespeichert: \(microphone.title)")
    }

    @objc private func cleanupChanged() {
        callbacks.onCleanupChanged(cleanupCheckbox.state == .on)
    }

    @objc private func soundsChanged() {
        callbacks.onSoundsChanged(soundsCheckbox.state == .on)
    }

    @objc private func loginItemChanged() {
        callbacks.onLoginItemChanged(loginCheckbox.state == .on)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === customWordsField else { return }
        callbacks.onCustomWordsChanged(customWordsField.stringValue)
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === replacementRulesView else { return }
        callbacks.onReplacementRulesChanged(replacementRulesView.string)
    }

    @objc private func testRecording() {
        callbacks.onTestRecording()
    }

    @objc private func copyLatestTranscript() {
        callbacks.onCopyLatestTranscript()
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
        callbacks.onCopyHistoryTranscript(transcript)
    }

    @objc private func retryModelDownload() {
        callbacks.onRetryModelDownload()
    }

    @objc private func checkForUpdates() {
        if let url = updateURL {
            NSWorkspace.shared.open(url)
        } else {
            callbacks.onCheckForUpdates()
        }
    }

    @objc private func startKeyCapture() {
        captureMonitor.map(NSEvent.removeMonitor)
        captureMonitor = nil
        learnKeyButton.isEnabled = false
        setStatus("Drücke jetzt die gewünschte Sprechtaste …")

        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .systemDefined]
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
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
        callbacks.onKeyChanged(key)
        setStatus("Gespeichert: \(key.title)")
    }

    private func learnedKey(from event: NSEvent) -> PushToTalkKey? {
        if event.type == .systemDefined,
           event.subtype.rawValue == 8,
           let mediaEvent = MediaKeyEvent(data1: event.data1),
           mediaEvent.isPressed {
            return .learnedMedia(keyCode: mediaEvent.keyCode, displayName: mediaKeyName(mediaEvent.keyCode))
        }

        if event.type == .flagsChanged {
            guard isModifierKeyCode(event.keyCode) else { return nil }
            return .learned(keyCode: event.keyCode, displayName: modifierKeyName(event.keyCode), isModifier: true)
        }

        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let known = PushToTalkKey.allCases.first { $0.keyCode == event.keyCode }
        return .learned(keyCode: event.keyCode, displayName: known?.title ?? keyName(for: event), isModifier: false)
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    private func modifierKeyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 54: return "Rechte Befehlstaste (⌘)"
        case 55: return "Linke Befehlstaste (⌘)"
        case 56: return "Linke Umschalttaste (⇧)"
        case 57: return "Feststelltaste"
        case 58: return "Linke Wahltaste (⌥)"
        case 59: return "Linke Control-Taste (⌃)"
        case 60: return "Rechte Umschalttaste (⇧)"
        case 61: return "Rechte Wahltaste (⌥)"
        case 62: return "Rechte Control-Taste (⌃)"
        case 63: return "Fn/Globe"
        default: return "Taste \(keyCode)"
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
        case 16: return "Play/Pause"
        case 17: return "Nächster Titel"
        case 18: return "Vorheriger Titel"
        default: return "Medientaste \(keyCode)"
        }
    }

    private static func microphoneSelections() -> [MicrophoneSelection] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices

        let manual = devices.map {
            MicrophoneSelection.manual(deviceID: $0.uniqueID, name: $0.localizedName)
        }
        return [.systemDefault] + manual
    }

    @objc private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
