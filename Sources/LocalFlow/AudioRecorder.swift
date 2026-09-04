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

        do {
            let url = Self.recordingURL
            try? FileManager.default.removeItem(at: url)

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
        recorder?.stop()
        recorder = nil
        restoreDefaultInputDevice()
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

    private static var recordingURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-recording.wav")
    }
}
