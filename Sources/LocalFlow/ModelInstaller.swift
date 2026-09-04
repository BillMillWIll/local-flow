import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

enum ModelInstaller {
    static var modelDirectory: URL {
        if let override = ProcessInfo.processInfo.environment[
            "LOCAL_FLOW_MODEL_DIRECTORY"
        ], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalFlow")
    }

    static func modelURL(for model: ModelFile) -> URL {
        modelDirectory.appendingPathComponent(model.fileName)
    }

    static func isInstalled(_ model: ModelFile) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: model).path)
    }

    /// All local files of the engine are present. Apple's language asset is
    /// checked separately because that lookup is asynchronous.
    static func hasLocalFiles(for engine: RecognitionEngine) -> Bool {
        engine.requiredFiles.allSatisfy(isInstalled)
    }

    static func missingFiles(for engine: RecognitionEngine) -> [ModelFile] {
        engine.requiredFiles.filter { !isInstalled($0) }
    }

    static func install(
        _ model: ModelFile,
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

final class ModelDownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
