import Foundation

/// The CLI tools write their transcript to a file, so stdout is disposable.
/// Drain stderr while the child is running: waiting first deadlocks when
/// either pipe fills up during a long dictation.
public enum LocalProcess {
    public struct Result: Sendable {
        public let status: Int32
        public let uncaughtSignal: Bool
        public let standardError: String
    }

    public static func run(_ executable: URL, arguments: [String]) throws -> Result {
        let errors = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      uncaughtSignal: process.terminationReason == .uncaughtSignal,
                      standardError: String(decoding: diagnostic, as: UTF8.self))
    }
}
