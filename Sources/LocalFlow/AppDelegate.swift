import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import LocalFlowCore
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Keys {
        static let pushToTalkKey = "pushToTalkKey"
        static let legacyWhisperModel = "whisperModel"
        static let recognitionEngine = "recognitionEngine"
        static let microphoneSelection = "microphoneSelection"
        static let transcriptHistory = "transcriptHistory"
        static let onboardingCompleted = "onboardingCompleted"
        static let customWords = "customWords"
        static let replacementRules = "replacementRules"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundsDisabled = "soundsDisabled"
    }

    private enum TranscriptionDestination {
        case paste
        case test
    }

    private let recorder = AudioRecorder()
    private let defaults = UserDefaults.standard
    private var hotkeyMonitor: PushToTalkMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var handsFreeMenuItem: NSMenuItem!
    private var cleanupMenuItem: NSMenuItem!
    private var copyLatestMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var pushToTalkState = PushToTalkState()
    private var doubleTap = DoubleTapDetector()
    private var selectedKey = PushToTalkKey.defaultKey
    private var selectedEngine = RecognitionEngine.parakeet
    private var selectedMicrophone = MicrophoneSelection.systemDefault
    private var customWordsText = ""
    private var replacementRulesText = ReplacementRules.defaultText
    private var cleanupEnabled = false
    private var soundsEnabled = true
    private var transcriptHistory = TranscriptHistory()
    private var isTestRecording = false
    private var isInstallingModel = false
    private var onboardingTestCompleted = false
    private var appleGermanInstalled = false
    private var deferredStatusReset = DeferredReset()
    private var maximumDurationTask: Task<Void, Never>?
    private var currentActivity = LocalFlowActivity.ready(keyTitle: "")

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        configureStatusItem()

        hotkeyMonitor = PushToTalkMonitor(
            key: selectedKey,
            onPress: { [weak self] in self?.pushToTalkPressed() },
            onRelease: { [weak self] in self?.pushToTalkReleased() },
            onEscape: { [weak self] in self?.cancelRecording() }
        )
        hotkeyMonitor?.start()
        configureSettingsWindow()
        configureOnboardingWindow()
        updateTranscriptHistoryViews()
        refreshPermissions()
        refreshOnboarding()
        setActivity(readyActivity)

        if defaults.bool(forKey: Keys.onboardingCompleted) {
            settingsWindowController?.show()
        } else {
            onboardingWindowController?.show()
        }

        Task {
            settingsWindowController?.refreshMicrophones(selected: selectedMicrophone)
            await refreshAppleSpeechState()
            await prepareSelectedEngineIfNeeded()
            await checkForUpdates(showCurrentResult: false)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissions()
        refreshOnboarding()
        settingsWindowController?.setCleanupAvailability(TextCleanup.availability())
        settingsWindowController?.setLoginItemEnabled(LoginItem.isEnabled)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioRecorder.discardAllRecordings()
    }

    private func loadSettings() {
        selectedKey = PushToTalkKey(savedValue: defaults.string(forKey: Keys.pushToTalkKey))
        selectedEngine = RecognitionEngine(
            savedValue: defaults.string(forKey: Keys.recognitionEngine),
            legacyWhisperModel: defaults.string(forKey: Keys.legacyWhisperModel),
            appleSupported: AppleSpeechSupport.isSupported
        )
        selectedMicrophone = MicrophoneSelection(savedValue: defaults.string(forKey: Keys.microphoneSelection))
        transcriptHistory = TranscriptHistory(entries: defaults.stringArray(forKey: Keys.transcriptHistory) ?? [])
        customWordsText = defaults.string(forKey: Keys.customWords) ?? ""
        replacementRulesText = defaults.string(forKey: Keys.replacementRules) ?? ReplacementRules.defaultText
        cleanupEnabled = defaults.bool(forKey: Keys.cleanupEnabled) && TextCleanup.availability().isAvailable
        soundsEnabled = !defaults.bool(forKey: Keys.soundsDisabled)
        if cleanupEnabled {
            TextCleanup.prewarm()
        }
    }

    // MARK: - Menu bar

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Local Flow")

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: readyText, action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        handsFreeMenuItem = NSMenuItem(
            title: "Freihändige Aufnahme starten",
            action: #selector(toggleHandsFreeFromMenu),
            keyEquivalent: ""
        )
        handsFreeMenuItem.target = self
        menu.addItem(handsFreeMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Einstellungen öffnen", action: #selector(openSettings), keyEquivalent: "")
        cleanupMenuItem = NSMenuItem(
            title: "Text mit Apple Intelligence bereinigen",
            action: #selector(toggleCleanupFromMenu),
            keyEquivalent: ""
        )
        cleanupMenuItem.target = self
        menu.addItem(cleanupMenuItem)
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
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Local Flow beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
        updateCleanupMenuItem()
    }

    private func updateCleanupMenuItem() {
        let availability = TextCleanup.availability()
        cleanupMenuItem.isEnabled = availability.isAvailable
        cleanupMenuItem.state = cleanupEnabled ? .on : .off
    }

    // MARK: - Windows

    private func configureSettingsWindow() {
        let state = SettingsWindowController.InitialState(
            selectedKey: selectedKey,
            selectedEngine: selectedEngine,
            availableEngines: RecognitionEngine.available(appleSupported: AppleSpeechSupport.isSupported),
            selectedMicrophone: selectedMicrophone,
            customWords: customWordsText,
            replacementRules: replacementRulesText,
            cleanupEnabled: cleanupEnabled,
            cleanupAvailability: TextCleanup.availability(),
            soundsEnabled: soundsEnabled,
            loginItemEnabled: LoginItem.isEnabled
        )
        let callbacks = SettingsWindowController.Callbacks(
            onKeyChanged: { [weak self] key in self?.changePushToTalkKey(to: key) },
            onEngineChanged: { [weak self] engine in self?.changeEngine(to: engine) },
            onMicrophoneChanged: { [weak self] microphone in self?.changeMicrophone(to: microphone) },
            onCustomWordsChanged: { [weak self] text in
                self?.customWordsText = text
                self?.defaults.set(text, forKey: Keys.customWords)
            },
            onReplacementRulesChanged: { [weak self] text in
                self?.replacementRulesText = text
                self?.defaults.set(text, forKey: Keys.replacementRules)
            },
            onCleanupChanged: { [weak self] enabled in self?.setCleanupEnabled(enabled) },
            onSoundsChanged: { [weak self] enabled in
                self?.soundsEnabled = enabled
                self?.defaults.set(!enabled, forKey: Keys.soundsDisabled)
            },
            onLoginItemChanged: { [weak self] enabled in self?.setLoginItemEnabled(enabled) },
            onTestRecording: { [weak self] in self?.beginTestRecording() },
            onCopyLatestTranscript: { [weak self] in self?.copyLatestTranscript() },
            onCopyHistoryTranscript: { [weak self] transcript in self?.copyTranscriptToPasteboard(transcript) },
            onRetryModelDownload: { [weak self] in Task { await self?.prepareSelectedEngineIfNeeded() } },
            onCheckForUpdates: { [weak self] in Task { await self?.checkForUpdates(showCurrentResult: true) } }
        )
        settingsWindowController = SettingsWindowController(state: state, callbacks: callbacks)
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
                Task { await self?.prepareSelectedEngineIfNeeded() }
            },
            onTestRecording: { [weak self] in self?.beginTestRecording() },
            onFinish: { [weak self] in
                self?.defaults.set(true, forKey: Keys.onboardingCompleted)
                self?.onboardingWindowController?.close()
                self?.settingsWindowController?.show()
            },
            onSkip: { [weak self] in
                self?.onboardingWindowController?.close()
                self?.settingsWindowController?.show()
            }
        )
    }

    private var isEngineReady: Bool {
        if selectedEngine.requiresAppleSpeech {
            return appleGermanInstalled
        }
        return ModelInstaller.hasLocalFiles(for: selectedEngine)
    }

    private func currentOnboardingProgress() -> OnboardingProgress {
        OnboardingProgress(
            microphoneAllowed: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibilityAllowed: AXIsProcessTrusted(),
            modelInstalled: isEngineReady,
            testRecordingCompleted: onboardingTestCompleted
        )
    }

    private func refreshOnboarding() {
        onboardingWindowController?.setProgress(currentOnboardingProgress())
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Settings changes

    private func changePushToTalkKey(to key: PushToTalkKey) {
        selectedKey = key
        defaults.set(key.rawValue, forKey: Keys.pushToTalkKey)
        hotkeyMonitor?.updateKey(key)
        doubleTap.reset()
        settingsWindowController?.setSelectedKey(key)
        showReadyIfIdle()
    }

    private func changeEngine(to engine: RecognitionEngine) {
        selectedEngine = engine
        defaults.set(engine.rawValue, forKey: Keys.recognitionEngine)
        settingsWindowController?.setModelDownloadProgress(nil)
        refreshOnboarding()
        showReadyIfIdle()
        Task { await prepareSelectedEngineIfNeeded() }
    }

    private func changeMicrophone(to microphone: MicrophoneSelection) {
        selectedMicrophone = microphone
        defaults.set(microphone.rawValue, forKey: Keys.microphoneSelection)
        showReadyIfIdle()
    }

    private func setCleanupEnabled(_ enabled: Bool) {
        cleanupEnabled = enabled && TextCleanup.availability().isAvailable
        defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled)
        if cleanupEnabled {
            TextCleanup.prewarm()
        }
        settingsWindowController?.setCleanupEnabled(cleanupEnabled)
        updateCleanupMenuItem()
        showReadyIfIdle()
    }

    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            show(error)
        }
        settingsWindowController?.setLoginItemEnabled(LoginItem.isEnabled)
    }

    // MARK: - Recording

    private var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func pushToTalkPressed() {
        let isDoubleTap = doubleTap.press(at: now)

        if pushToTalkState.isHandsFree {
            if pushToTalkState.press() == .stopRecording {
                stopAndTranscribe(destination: .paste)
            }
            return
        }

        if isDoubleTap, pushToTalkState.isRecording {
            // The first tap's recording is still starting; keep it running.
            pushToTalkState.enableHandsFree()
            setActivity(.handsFreeRecording)
            return
        }

        guard !isTestRecording, !isInstallingModel else { return }
        guard isEngineReady else {
            Task { await prepareSelectedEngineIfNeeded() }
            return
        }
        guard pushToTalkState.press() == .startRecording else { return }
        if isDoubleTap {
            pushToTalkState.enableHandsFree()
        }
        startRecording()
    }

    private func pushToTalkReleased() {
        doubleTap.release(at: now)
        guard pushToTalkState.release() == .stopRecording else { return }
        stopAndTranscribe(destination: .paste)
    }

    private func startRecording() {
        let handsFree = pushToTalkState.isHandsFree
        setActivity(handsFree ? .handsFreeRecording : .recording)

        Task {
            do {
                // Der Ton läuft vor der Aufnahme, sonst landet er im Transkript.
                await playSoundAndWait(.start)
                try await recorder.start(microphone: selectedMicrophone)
                guard pushToTalkState.isRecording else {
                    // Cancelled with Esc while the recorder was starting.
                    recorder.cancel()
                    return
                }
                scheduleMaximumDuration()
                if pushToTalkState.isHandsFree {
                    setActivity(.handsFreeRecording)
                }
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

    private func scheduleMaximumDuration() {
        maximumDurationTask?.cancel()
        maximumDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RecordingGuard.maximumDuration))
            guard !Task.isCancelled, let self else { return }
            if pushToTalkState.stop() == .stopRecording {
                stopAndTranscribe(destination: .paste)
            }
        }
    }

    @objc private func toggleHandsFreeFromMenu() {
        if pushToTalkState.isRecording {
            if pushToTalkState.stop() == .stopRecording {
                stopAndTranscribe(destination: .paste)
            }
            return
        }
        guard !isTestRecording, !isInstallingModel else { return }
        guard isEngineReady else {
            Task { await prepareSelectedEngineIfNeeded() }
            return
        }
        guard pushToTalkState.press() == .startRecording else { return }
        pushToTalkState.enableHandsFree()
        startRecording()
    }

    private func cancelRecording() {
        guard pushToTalkState.cancel() else { return }
        maximumDurationTask?.cancel()
        recorder.cancel()
        doubleTap.reset()
        playSound(.cancel)
        setActivity(.cancelled)
        resetStatusSoon()
    }

    private func beginTestRecording() {
        guard !isTestRecording, !isInstallingModel, !pushToTalkState.isRecording else { return }
        guard isEngineReady else {
            Task { await prepareSelectedEngineIfNeeded() }
            return
        }
        isTestRecording = true
        settingsWindowController?.setTestRecordingEnabled(false)
        settingsWindowController?.setTestResult("Testaufnahme läuft …")
        onboardingWindowController?.setTestRunning(true)
        setActivity(.testRecording)

        Task {
            do {
                await playSoundAndWait(.start)
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

    // MARK: - Transcription

    private func stopAndTranscribe(destination: TranscriptionDestination) {
        maximumDurationTask?.cancel()
        let duration = recorder.currentDuration

        do {
            let audioURL = try recorder.stop()
            playSound(.stop)

            if destination == .paste, !RecordingGuard.isLongEnough(duration) {
                AudioRecorder.discard(audioURL)
                finishProcessing(destination: destination)
                setActivity(.tooShort)
                resetStatusSoon()
                return
            }

            setActivity(.processing)
            let engine = EngineFactory.make(selectedEngine)
            let options = TranscriptionOptions(customWords: CustomWords.parse(customWordsText))
            let rules = ReplacementRules.parse(replacementRulesText)
            let shouldClean = cleanupEnabled

            Task {
                let result: Result<String, Error>
                do {
                    let raw = try await engine.transcribe(audioURL: audioURL, options: options)
                    var text = ReplacementRules.apply(rules, to: raw)
                    if shouldClean, !text.isEmpty {
                        setActivity(.cleaning)
                        text = await TextCleanup.clean(text)
                    }
                    let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if final.isEmpty {
                        result = .failure(LocalFlowError.emptyTranscript)
                    } else {
                        result = .success(final)
                    }
                } catch {
                    result = .failure(error)
                }
                AudioRecorder.discard(audioURL)
                handleTranscription(result, destination: destination)
            }
        } catch {
            finishProcessing(destination: destination)
            show(error)
        }
    }

    private func handleTranscription(_ result: Result<String, Error>, destination: TranscriptionDestination) {
        finishProcessing(destination: destination)
        do {
            let transcript = try result.get()
            recordTranscript(transcript)

            switch destination {
            case .paste:
                try TextInserter.paste(transcript)
                setActivity(.success("Eingefügt"))
            case .test:
                settingsWindowController?.setTestResult(transcript)
                onboardingTestCompleted = true
                refreshOnboarding()
                setActivity(.success("Test fertig"))
            }
            resetStatusSoon()
        } catch {
            if destination == .test {
                settingsWindowController?.setTestResult("Fehler: \(error.localizedDescription)")
            }
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
        defaults.set(transcriptHistory.entries, forKey: Keys.transcriptHistory)
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
            let preview = transcript.count > 60 ? String(transcript.prefix(60)) + " …" : transcript
            let item = NSMenuItem(
                title: "\(index + 1). \(preview.replacingOccurrences(of: "\n", with: " "))",
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

    @objc private func toggleCleanupFromMenu() {
        setCleanupEnabled(!cleanupEnabled)
    }

    private func copyTranscriptToPasteboard(_ transcript: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        settingsWindowController?.setTestResult("Kopiert: \(transcript)")
        setActivity(.success("Text kopiert"))
        resetStatusSoon()
    }

    // MARK: - Engine preparation

    private func refreshAppleSpeechState() async {
        guard AppleSpeechSupport.isSupported else { return }
        appleGermanInstalled = await AppleSpeechSupport.isGermanInstalled()
        refreshOnboarding()
    }

    private func prepareSelectedEngineIfNeeded() async {
        let engine = selectedEngine
        if engine.requiresAppleSpeech {
            await refreshAppleSpeechState()
            if appleGermanInstalled {
                settingsWindowController?.setEngineDetail(engine.detail)
                return
            }
        } else if ModelInstaller.hasLocalFiles(for: engine) {
            settingsWindowController?.setEngineDetail(engine.detail)
            return
        }

        guard !isInstallingModel else { return }
        isInstallingModel = true
        defer {
            isInstallingModel = false
            refreshOnboarding()
        }

        let progressHandler: @Sendable (ModelDownloadProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.settingsWindowController?.setModelDownloadProgress(progress)
                self?.onboardingWindowController?.setModelProgress(progress)
                self?.setActivity(.downloadingModel(progress.percentage))
            }
        }

        settingsWindowController?.setModelDownloadProgress(
            ModelDownloadProgress(receivedBytes: 0, totalBytes: nil)
        )
        onboardingWindowController?.setModelProgress(
            ModelDownloadProgress(receivedBytes: 0, totalBytes: nil)
        )
        setActivity(.downloadingModel(nil))

        do {
            if engine.requiresAppleSpeech {
                settingsWindowController?.setEngineDetail("Apple lädt das deutsche Sprachpaket einmalig.")
                try await AppleSpeechSupport.installGerman(progress: progressHandler)
                appleGermanInstalled = await AppleSpeechSupport.isGermanInstalled()
                guard appleGermanInstalled else { throw LocalFlowError.appleSpeechUnavailable }
            } else {
                for file in ModelInstaller.missingFiles(for: engine) {
                    settingsWindowController?.setEngineDetail(
                        "Einmaliger Download: \(file.fileName) (\(file.sizeDescription))"
                    )
                    try await ModelInstaller.install(file, progress: progressHandler)
                }
            }
            settingsWindowController?.setModelDownloadProgress(nil)
            settingsWindowController?.setEngineDetail(engine.detail)
            refreshOnboarding()
            setActivity(.success("\(engine.shortTitle) ist bereit"))
            resetStatusSoon()
        } catch {
            settingsWindowController?.setModelDownloadFailed()
            onboardingWindowController?.setModelDownloadFailed()
            settingsWindowController?.setEngineDetail(error.localizedDescription)
            show(error)
        }

        if selectedEngine != engine {
            // The user switched engines while this one was downloading.
            Task { await prepareSelectedEngineIfNeeded() }
        }
    }

    // MARK: - Updates

    private func checkForUpdates(showCurrentResult: Bool) async {
        do {
            let release = try await UpdateChecker.latestRelease()
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let decision = UpdateDecision(current: currentVersion, latestTag: release.tagName)

            if decision.isUpdateAvailable {
                let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                settingsWindowController?.setUpdateAvailable(version: version, url: release.htmlURL)
                updateMenuItem.title = "Update \(version) laden"
                updateMenuItem.representedObject = release.htmlURL
            } else if showCurrentResult {
                settingsWindowController?.setUpdateCheckResult("App ist aktuell")
                setActivity(.success("Local Flow ist aktuell"))
                resetStatusSoon()
            }
        } catch {
            if showCurrentResult {
                settingsWindowController?.setUpdateCheckResult("Update-Prüfung wiederholen")
                setActivity(.failure("Update-Prüfung fehlgeschlagen"))
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

    // MARK: - Status

    private func show(_ error: Error) {
        NSSound.beep()
        var message = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
        if message.count > 140 {
            message = String(message.prefix(140)) + " …"
        }
        setActivity(.failure(message))
        resetStatusSoon()
    }

    private func playSound(_ kind: SoundFeedback.Kind) {
        guard soundsEnabled else { return }
        SoundFeedback.play(kind)
    }

    private func playSoundAndWait(_ kind: SoundFeedback.Kind) async {
        guard soundsEnabled else { return }
        SoundFeedback.play(kind)
        try? await Task.sleep(for: .milliseconds(120))
    }

    private var readyActivity: LocalFlowActivity {
        .ready(keyTitle: selectedKey.title)
    }

    /// Settings changes refresh the ready line, but never while a dictation
    /// or a test recording is in progress.
    private func showReadyIfIdle() {
        guard pushToTalkState.isIdle, !isTestRecording, !isInstallingModel else { return }
        if case .ready = currentActivity {
            setActivity(readyActivity)
        }
    }

    private var readyText: String {
        var parts = ["Bereit: \(selectedKey.title)", selectedEngine.shortTitle]
        if cleanupEnabled {
            parts.append("bereinigt")
        }
        return parts.joined(separator: " · ")
    }

    private func setActivity(_ activity: LocalFlowActivity) {
        deferredStatusReset.invalidate()
        currentActivity = activity

        if case .ready = activity {
            statusMenuItem.title = readyText
        } else {
            statusMenuItem.title = activity.title
        }
        handsFreeMenuItem.title = pushToTalkState.isRecording
            ? "Aufnahme beenden und einfügen"
            : "Freihändige Aufnahme starten"
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, deferredStatusReset.isCurrent(token) else { return }
            setActivity(readyActivity)
        }
    }

    @objc private func openSettings() {
        refreshPermissions()
        settingsWindowController?.refreshMicrophones(selected: selectedMicrophone)
        settingsWindowController?.setCleanupAvailability(TextCleanup.availability())
        settingsWindowController?.setCleanupEnabled(cleanupEnabled)
        settingsWindowController?.setLoginItemEnabled(LoginItem.isEnabled)
        settingsWindowController?.show()
    }
}
