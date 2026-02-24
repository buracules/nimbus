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

    private static var colorsEnabled: Bool {
        isatty(fileno(stdout)) != 0
    }

    static func colored(_ text: String, _ color: Color) -> String {
        guard colorsEnabled else { return text }
        return "\(color.rawValue)\(text)\(Color.reset.rawValue)"
    }

    static func info(_ message: String) {
        print("\(colored("▸", .cyan)) \(message)")
    }

    static func success(_ message: String) {
        print("\(colored("✓", .green)) \(message)")
    }

    static func warning(_ message: String) {
        print("\(colored("⚠", .yellow)) \(message)")
    }

    static func error(_ message: String) {
        var stderr = FileHandle.standardError
        print("\(colored("✗", .red)) \(message)", to: &stderr)
    }

    static func step(_ message: String) {
        print("\(colored("▸", .bold)) \(message)")
    }

    static func verbose(_ message: String, isVerbose: Bool) {
        guard isVerbose else { return }
        print("\(colored("  ›", .dim)) \(message)")
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
