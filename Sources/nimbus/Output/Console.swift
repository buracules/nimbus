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

    /// The stream a line actually lands on. Colour is decided per stream
    /// because narration and errors do not share a destination: `error()`
    /// always writes to stderr, which may be a terminal while stdout is piped.
    enum Stream {
        case out
        case err
    }

    /// Neither the environment nor a file descriptor's tty-ness changes while
    /// the process runs, so both are resolved once rather than per emitted line.
    private static let noColorRequested = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
    private static let stdoutIsTerminal = isatty(fileno(stdout)) != 0
    private static let stderrIsTerminal = isatty(fileno(stderr)) != 0

    /// The colour decision, as a pure function of its inputs so it can be
    /// tested without a terminal or a mutated environment.
    ///
    /// `NO_COLOR` follows the https://no-color.org convention: any value, even
    /// an empty one, disables colour.
    static func shouldColor(noColor: Bool, machineReadable: Bool, isTerminal: Bool) -> Bool {
        guard !noColor, !machineReadable else { return false }
        return isTerminal
    }

    private static func colorsEnabled(on stream: Stream) -> Bool {
        shouldColor(
            noColor: noColorRequested,
            machineReadable: isMachineReadable,
            isTerminal: stream == .out ? stdoutIsTerminal : stderrIsTerminal
        )
    }

    static func colored(_ text: String, _ color: Color, on stream: Stream = .out) -> String {
        guard colorsEnabled(on: stream) else { return text }
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
        print("\(colored("✗", .red, on: .err)) \(message)", to: &stderr)
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
