import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var inputDeviceRestoration = TemporaryValueRestoration<AudioDeviceID>()

    func start(microphone: MicrophoneSelection) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw LocalFlowError.microphoneDenied
        }

        if let deviceID = microphone.deviceID {
            try switchDefaultInputDevice(to: deviceID)
        }

        if let previous = recorder {
            previous.stop()
            self.recorder = nil
            try? FileManager.default.removeItem(at: previous.url)
        }

        do {
            let url = Self.makeRecordingURL()

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
                throw LocalFlowError.recordingFailed
            }
            self.recorder = recorder
        } catch {
            restoreDefaultInputDevice()
            throw error
        }
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
        if let recorder {
            recorder.stop()
            Self.discard(recorder.url)
        }
        recorder = nil
        restoreDefaultInputDevice()
    }

    /// Seconds recorded so far, 0 when idle.
    var currentDuration: TimeInterval {
        recorder?.currentTime ?? 0
    }

    /// Recordings are private; nothing stays on disk after a dictation.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes leftovers from crashed or force-quit sessions.
    static func discardAllRecordings() {
        let directory = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("local-flow-recording") && file.hasSuffix(".wav") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    private func switchDefaultInputDevice(to uniqueID: String) throws {
        guard var selectedDeviceID = Self.audioDeviceID(for: uniqueID) else {
            throw LocalFlowError.recordingFailed
        }

        let currentDeviceID = try Self.defaultInputDeviceID()
        inputDeviceRestoration.remember(currentDeviceID)

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
            _ = inputDeviceRestoration.takeRememberedValue()
            throw LocalFlowError.recordingFailed
        }
    }

    private func restoreDefaultInputDevice() {
        guard var deviceID = inputDeviceRestoration.takeRememberedValue() else {
            return
        }

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

    private static func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-recording-\(UUID().uuidString).wav")
    }
}
