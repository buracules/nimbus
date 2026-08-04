import Foundation

struct BuildTimer {
    private let start: CFAbsoluteTime

    init() {
        self.start = CFAbsoluteTimeGetCurrent()
    }

    var elapsed: TimeInterval {
        CFAbsoluteTimeGetCurrent() - start
    }

    var formatted: String {
        Self.format(elapsed)
    }

    /// Render a duration the way nimbus reports build times.
    static func format(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainingSeconds = seconds - Double(minutes * 60)
        return String(format: "%dm %.1fs", minutes, remainingSeconds)
    }
}
