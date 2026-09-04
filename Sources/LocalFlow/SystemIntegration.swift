import AppKit
import ServiceManagement

/// Short system sounds that confirm the recording state without looking.
enum SoundFeedback {
    enum Kind {
        case start
        case stop
        case cancel
    }

    static func play(_ kind: Kind) {
        let name: String
        switch kind {
        case .start:
            name = "Tink"
        case .stop:
            name = "Pop"
        case .cancel:
            name = "Bottle"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

/// Start at login through the system-managed login item.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
