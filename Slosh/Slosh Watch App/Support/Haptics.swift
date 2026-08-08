import OceanCore
import WatchKit

/// Plays a tap when the water breaks, rate-limited so a rough ride doesn't
/// turn into a continuous buzz against the wrist.
final class Haptics {
    private var lastPlayed: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.8

    var isEnabled = true

    func playBreak(_ kind: HapticKind?) {
        guard isEnabled, let kind else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) >= minimumInterval else { return }
        lastPlayed = now
        WKInterfaceDevice.current().play(kind.watchType)
    }

    /// A light confirmation for picking a theme — always plays, never throttled.
    func playSelection() {
        guard isEnabled else { return }
        WKInterfaceDevice.current().play(.click)
    }
}

extension HapticKind {
    var watchType: WKHapticType {
        switch self {
        case .click: .click
        case .directionUp: .directionUp
        case .notification: .notification
        case .start: .start
        case .stop: .stop
        }
    }
}
