import Foundation

public enum WhisperModel: String, CaseIterable, Sendable {
    case small
    case largeTurbo

    public static let defaultModel = WhisperModel.small

    public init(savedValue: String?) {
        self = savedValue.flatMap(Self.init(rawValue:)) ?? Self.defaultModel
    }

    public var title: String {
        switch self {
        case .small:
            return "Small Q5_1 – schneller"
        case .largeTurbo:
            return "Large v3 Turbo Q5_0 – genauer"
        }
    }

    public var fileName: String {
        switch self {
        case .small:
            return "ggml-small-q5_1.bin"
        case .largeTurbo:
            return "ggml-large-v3-turbo-q5_0.bin"
        }
    }

    public var downloadURL: URL {
        URL(
            string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)"
        )!
    }

    public var sha256: String {
        switch self {
        case .small:
            return "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
        case .largeTurbo:
            return "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
        }
    }
}

public struct TranscriptHistory: Equatable, Sendable {
    public static let limit = 5

    public private(set) var entries: [String]

    public var latest: String? {
        entries.first
    }

    public var displayItems: [String] {
        entries.enumerated().map { index, transcript in
            "\(index + 1). \(transcript)"
        }
    }

    public init(entries: [String] = []) {
        self.entries = Array(
            entries
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(Self.limit)
        )
    }

    public mutating func record(_ transcript: String) {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        entries.insert(cleaned, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }
}

public enum MicrophoneSelection: Equatable, Sendable {
    case systemDefault
    case manual(deviceID: String, name: String)

    public init(savedValue: String?) {
        guard let savedValue, savedValue != Self.systemDefault.rawValue else {
            self = .systemDefault
            return
        }

        let parts = savedValue.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "manual" else {
            self = .systemDefault
            return
        }

        self = .manual(deviceID: parts[1], name: parts[2])
    }

    public var rawValue: String {
        switch self {
        case .systemDefault:
            return "systemDefault"
        case .manual(let deviceID, let name):
            return "manual:\(deviceID):\(name)"
        }
    }

    public var title: String {
        switch self {
        case .systemDefault:
            return "Systemstandard verwenden"
        case .manual(_, let name):
            return name
        }
    }

    public var deviceID: String? {
        switch self {
        case .systemDefault:
            return nil
        case .manual(let deviceID, _):
            return deviceID
        }
    }
}

public struct PushToTalkKey: Equatable, Hashable, Sendable {
    public enum ModifierKind: Sendable {
        case none
        case option
        case command
        case control
        case shift
        case capsLock
        case function
    }

    public let rawValue: String
    public let title: String
    public let keyCode: UInt16
    public let isModifier: Bool
    public let mediaKeyCode: Int?

    public var modifierKind: ModifierKind {
        guard isModifier else { return .none }

        switch keyCode {
        case 58, 61:
            return .option
        case 54, 55:
            return .command
        case 59, 62:
            return .control
        case 56, 60:
            return .shift
        case 57:
            return .capsLock
        case 63:
            return .function
        default:
            return .none
        }
    }

    public static let rightOption = PushToTalkKey(
        rawValue: "rightOption",
        title: "Rechte Wahltaste (⌥)",
        keyCode: 61,
        isModifier: true,
        mediaKeyCode: nil
    )
    public static let leftOption = PushToTalkKey(
        rawValue: "leftOption",
        title: "Linke Wahltaste (⌥)",
        keyCode: 58,
        isModifier: true,
        mediaKeyCode: nil
    )
    public static let rightCommand = PushToTalkKey(
        rawValue: "rightCommand",
        title: "Rechte Befehlstaste (⌘)",
        keyCode: 54,
        isModifier: true,
        mediaKeyCode: nil
    )
    public static let leftCommand = PushToTalkKey(
        rawValue: "leftCommand",
        title: "Linke Befehlstaste (⌘)",
        keyCode: 55,
        isModifier: true,
        mediaKeyCode: nil
    )
    public static let f8 = PushToTalkKey(
        rawValue: "f8",
        title: "F8",
        keyCode: 100,
        isModifier: false,
        mediaKeyCode: 16
    )
    public static let f9 = PushToTalkKey(
        rawValue: "f9",
        title: "F9",
        keyCode: 101,
        isModifier: false,
        mediaKeyCode: 17
    )

    public static let allCases: [PushToTalkKey] = [
        .rightOption,
        .leftOption,
        .rightCommand,
        .leftCommand,
        .f8,
        .f9
    ]

    public static let defaultKey = PushToTalkKey.rightOption

    public init(savedValue: String?) {
        guard let savedValue else {
            self = Self.defaultKey
            return
        }

        if let known = Self.allCases.first(where: { $0.rawValue == savedValue }) {
            self = known
            return
        }

        if let learned = Self.parseLearned(savedValue) {
            self = learned
            return
        }

        self = Self.defaultKey
    }

    private init(
        rawValue: String,
        title: String,
        keyCode: UInt16,
        isModifier: Bool,
        mediaKeyCode: Int?
    ) {
        self.rawValue = rawValue
        self.title = title
        self.keyCode = keyCode
        self.isModifier = isModifier
        self.mediaKeyCode = mediaKeyCode
    }

    public static func learned(
        keyCode: UInt16,
        displayName: String,
        isModifier: Bool
    ) -> PushToTalkKey {
        let kind = isModifier ? "modifier" : "key"
        return PushToTalkKey(
            rawValue: "learned:\(kind):\(keyCode):\(displayName)",
            title: displayName,
            keyCode: keyCode,
            isModifier: isModifier,
            mediaKeyCode: nil
        )
    }

    public static func learnedMedia(
        keyCode: Int,
        displayName: String
    ) -> PushToTalkKey {
        PushToTalkKey(
            rawValue: "learned:media:\(keyCode):\(displayName)",
            title: displayName,
            keyCode: 0,
            isModifier: false,
            mediaKeyCode: keyCode
        )
    }

    private static func parseLearned(_ value: String) -> PushToTalkKey? {
        let parts = value.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4, parts[0] == "learned" else { return nil }

        switch parts[1] {
        case "key":
            guard let keyCode = UInt16(parts[2]) else { return nil }
            return .learned(
                keyCode: keyCode,
                displayName: parts[3],
                isModifier: false
            )
        case "modifier":
            guard let keyCode = UInt16(parts[2]) else { return nil }
            return .learned(
                keyCode: keyCode,
                displayName: parts[3],
                isModifier: true
            )
        case "media":
            guard let keyCode = Int(parts[2]) else { return nil }
            return .learnedMedia(keyCode: keyCode, displayName: parts[3])
        default:
            return nil
        }
    }
}

public struct MediaKeyEvent: Equatable, Sendable {
    public let keyCode: Int
    public let isPressed: Bool

    public init(keyCode: Int, isPressed: Bool) {
        self.keyCode = keyCode
        self.isPressed = isPressed
    }

    public init?(data1: Int) {
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let state = (data1 & 0x0000FF00) >> 8

        switch state {
        case 0x0A:
            self.init(keyCode: keyCode, isPressed: true)
        case 0x0B:
            self.init(keyCode: keyCode, isPressed: false)
        default:
            return nil
        }
    }
}

public enum TranscriptCleaner {
    private static let noiseMarkers = [
        "[BLANK_AUDIO]",
        "[MUSIC]",
        "[Music]",
        "[Applause]",
        "(Musik)"
    ]

    public static func clean(_ transcript: String) -> String {
        let withoutNoise = noiseMarkers.reduce(transcript) { text, marker in
            text.replacingOccurrences(of: marker, with: " ")
        }

        return withoutNoise
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct WhisperInvocation: Sendable {
    public let modelPath: String
    public let audioPath: String
    public let outputPath: String
    public let language: String

    public init(
        modelPath: String,
        audioPath: String,
        outputPath: String,
        language: String = "de"
    ) {
        self.modelPath = modelPath
        self.audioPath = audioPath
        self.outputPath = outputPath
        self.language = language
    }

    public var arguments: [String] {
        [
            "-m", modelPath,
            "-f", audioPath,
            "-l", language,
            "-otxt",
            "-of", outputPath,
            "-np"
        ]
    }
}

public struct PushToTalkState: Sendable {
    public enum Action: Sendable {
        case none
        case startRecording
        case stopRecording
    }

    private enum Phase: Sendable {
        case idle
        case starting
        case recording
        case waitingToStop
        case processing
    }

    private var phase: Phase = .idle

    public init() {}

    public mutating func press() -> Action {
        guard phase == .idle else { return .none }
        phase = .starting
        return .startRecording
    }

    public mutating func release() -> Action {
        switch phase {
        case .starting:
            phase = .waitingToStop
            return .none
        case .recording:
            phase = .processing
            return .stopRecording
        case .idle, .waitingToStop, .processing:
            return .none
        }
    }

    public mutating func recordingDidStart() -> Action {
        switch phase {
        case .starting:
            phase = .recording
            return .none
        case .waitingToStop:
            phase = .processing
            return .stopRecording
        case .idle, .recording, .processing:
            return .none
        }
    }

    public mutating func recordingDidFail() {
        phase = .idle
    }

    public mutating func processingDidFinish() {
        phase = .idle
    }
}
