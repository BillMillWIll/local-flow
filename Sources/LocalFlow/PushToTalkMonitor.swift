import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import CryptoKit
import LocalFlowCore
import QuartzCore

@MainActor
final class PushToTalkMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPressed = false
    private var key: PushToTalkKey
    private let onPress: () -> Void
    private let onRelease: () -> Void

    init(
        key: PushToTalkKey,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.key = key
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        let events: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .keyUp, .systemDefined
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func updateKey(_ key: PushToTalkKey) {
        isPressed = false
        self.key = key
    }

    private func handle(_ event: NSEvent) {
        if event.type == .systemDefined {
            handleMediaKey(event)
            return
        }

        guard event.keyCode == key.keyCode else { return }

        let pressed: Bool
        if key.isModifier {
            guard event.type == .flagsChanged else { return }
            pressed = modifierIsPressed(in: event)
        } else {
            guard event.type == .keyDown || event.type == .keyUp else { return }
            guard !event.isARepeat else { return }
            pressed = event.type == .keyDown
        }

        updatePressedState(pressed)
    }

    private func handleMediaKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8,
              let expectedCode = key.mediaKeyCode,
              let mediaEvent = MediaKeyEvent(data1: event.data1),
              mediaEvent.keyCode == expectedCode
        else {
            return
        }

        updatePressedState(mediaEvent.isPressed)
    }

    private func updatePressedState(_ pressed: Bool) {
        if pressed, !isPressed {
            isPressed = true
            onPress()
        } else if !pressed, isPressed {
            isPressed = false
            onRelease()
        }
    }

    private func modifierIsPressed(in event: NSEvent) -> Bool {
        switch key.modifierKind {
        case .option:
            return event.modifierFlags.contains(.option)
        case .command:
            return event.modifierFlags.contains(.command)
        case .control:
            return event.modifierFlags.contains(.control)
        case .shift:
            return event.modifierFlags.contains(.shift)
        case .capsLock:
            return event.modifierFlags.contains(.capsLock)
        case .function:
            return event.modifierFlags.contains(.function)
        case .none:
            return false
        }
    }
}
