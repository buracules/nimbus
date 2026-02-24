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
        let seconds = elapsed
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainingSeconds = seconds - Double(minutes * 60)
        return String(format: "%dm %.1fs", minutes, remainingSeconds)
    }
}
