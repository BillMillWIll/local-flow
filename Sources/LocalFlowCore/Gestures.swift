import Foundation

/// Detects a quick double tap on the push-to-talk key, which switches the
/// next recording into hands-free mode.
public struct DoubleTapDetector: Sendable {
    public let window: TimeInterval
    public let maximumHold: TimeInterval
    private var lastPress: TimeInterval?
    private var lastRelease: TimeInterval?
    private var ignoresNextRelease = false

    public init(window: TimeInterval = 0.4, maximumHold: TimeInterval = 0.3) {
        self.window = window
        self.maximumHold = maximumHold
    }

    /// Returns `true` when this press completes a double tap.
    public mutating func press(at time: TimeInterval) -> Bool {
        defer { lastPress = time }

        guard let lastPress, let lastRelease,
              lastRelease >= lastPress,
              lastRelease - lastPress <= maximumHold,
              time - lastRelease <= window
        else {
            return false
        }

        self.lastRelease = nil
        ignoresNextRelease = true
        return true
    }

    public mutating func release(at time: TimeInterval) {
        if ignoresNextRelease {
            ignoresNextRelease = false
            lastRelease = nil
            return
        }
        lastRelease = time
    }

    public mutating func reset() {
        lastPress = nil
        lastRelease = nil
        ignoresNextRelease = false
    }
}
