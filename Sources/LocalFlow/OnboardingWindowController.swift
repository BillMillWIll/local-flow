import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

@MainActor
final class OnboardingWindowController: NSWindowController {
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let microphoneSymbol = NSImageView()
    private let microphoneDetail = NSTextField(labelWithString: "Mikrofonzugriff erlauben")
    private let microphoneButton = NSButton()
    private let accessibilitySymbol = NSImageView()
    private let accessibilityDetail = NSTextField(labelWithString: "Bedienungshilfen erlauben")
    private let accessibilityButton = NSButton()
    private let modelSymbol = NSImageView()
    private let modelDetail = NSTextField(labelWithString: "Spracherkennung vorbereiten")
    private let modelButton = NSButton()
    private let testSymbol = NSImageView()
    private let testDetail = NSTextField(labelWithString: "Kurze Testaufnahme durchführen")
    private let testButton = NSButton()
    private let finishButton = NSButton()
    private var modelPresentation = ModelInstallationPresentation.missing
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
            completedText: "Spracherkennung ist bereit"
        )
        if progress.modelInstalled {
            modelPresentation = .installed
        } else if modelPresentation == .installed {
            modelPresentation = .missing
        }
        applyModelPresentation()
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
        modelPresentation = .installing(progress.percentage)
        applyModelPresentation()
    }

    func setModelDownloadFailed() {
        modelPresentation = .failed
        applyModelPresentation()
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

        modelButton.title = "Vorbereiten"
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

    private func applyModelPresentation() {
        modelDetail.stringValue = modelPresentation.detail
        modelButton.isEnabled = modelPresentation.isButtonEnabled
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
