import OceanCore
import WatchKit

/// Plays a tap when the water breaks, rate-limited so a rough ride doesn't
/// turn into a continuous buzz against the wrist.
final class Haptics {
    private var lastPlayed: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.8

    var isEnabled = true
    #if DEBUG
    var onAttempt: ((HapticKind?, Bool, String) -> Void)?
    #endif

    func playBreak(_ kind: HapticKind?) {
        guard isEnabled else {
            #if DEBUG
            onAttempt?(kind, false, "disabled")
            #endif
            return
        }
        guard let kind else {
            #if DEBUG
            onAttempt?(nil, false, "mode-has-no-haptic")
            #endif
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) >= minimumInterval else {
            #if DEBUG
            onAttempt?(kind, false, "rate-limited")
            #endif
            return
        }
        lastPlayed = now
        WKInterfaceDevice.current().play(kind.watchType)
        #if DEBUG
        onAttempt?(kind, true, "played")
        #endif
    }

    /// A light confirmation for picking a theme — always plays, never throttled.
    func playSelection() {
        guard isEnabled else {
            #if DEBUG
            onAttempt?(.click, false, "disabled")
            #endif
            return
        }
        WKInterfaceDevice.current().play(.click)
        #if DEBUG
        onAttempt?(.click, true, "selection")
        #endif
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
