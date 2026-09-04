import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private var deferredStatusReset = DeferredReset()

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
            onboardingWindowController?.setModelDownloadFailed()
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
        deferredStatusReset.invalidate()

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
        let token = deferredStatusReset.schedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, deferredStatusReset.isCurrent(token) else { return }
            updateStatus(readyText, symbol: "mic")
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
