import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

func runModelDownloadDiagnostic(model: WhisperModel) -> Never {
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
