import Foundation

enum Console {
    enum Color: String {
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        case bold = "\u{001B}[1m"
        case dim = "\u{001B}[2m"
        case reset = "\u{001B}[0m"
    }

    /// True when stdout is carrying a machine-readable envelope rather than
    /// text for a human.
    ///
    /// One writer: `CommandRunner` sets it once, before the command body runs
    /// and therefore before any subprocess or stream queue exists. Everything
    /// else only reads it.
    private(set) static var isMachineReadable = false

    static func setMachineReadable(_ enabled: Bool) {
        isMachineReadable = enabled
    }

    private static var colorsEnabled: Bool {
        !isMachineReadable && isatty(fileno(stdout)) != 0
    }

    static func colored(_ text: String, _ color: Color) -> String {
        guard colorsEnabled else { return text }
        return "\(color.rawValue)\(text)\(Color.reset.rawValue)"
    }

    /// Where narration goes.
    ///
    /// Under `--json` stdout is reserved for the envelope, so everything a
    /// human would have read moves to stderr rather than disappearing — the
    /// information is still there for whoever is watching, it just stops
    /// corrupting the parse.
    private static func narrate(_ line: String) {
        if isMachineReadable {
            var stderr = FileHandle.standardError
            print(line, to: &stderr)
        } else {
            print(line)
        }
    }

    static func info(_ message: String) {
        narrate("\(colored("▸", .cyan)) \(message)")
    }

    static func success(_ message: String) {
        narrate("\(colored("✓", .green)) \(message)")
    }

    static func warning(_ message: String) {
        narrate("\(colored("⚠", .yellow)) \(message)")
    }

    static func error(_ message: String) {
        var stderr = FileHandle.standardError
        print("\(colored("✗", .red)) \(message)", to: &stderr)
    }

    static func step(_ message: String) {
        narrate("\(colored("▸", .bold)) \(message)")
    }

    /// An unadorned line that belongs with whatever was just narrated —
    /// a continuation, a blank separator, an echoed file.
    static func detail(_ message: String = "") {
        narrate(message)
    }

    static func verbose(_ message: String, isVerbose: Bool) {
        guard isVerbose else { return }
        narrate("\(colored("  ›", .dim)) \(message)")
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
