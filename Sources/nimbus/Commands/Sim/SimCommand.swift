import ArgumentParser
import Foundation

/// `nimbus sim` — simctl operations against the simulator a command resolves
/// the same way build/run/test do, so `--device`, `--os` and `--interactive`
/// work uniformly across the whole family.
struct SimCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sim",
        abstract: "Control the simulator",
        subcommands: [
            SimScreenshotCommand.self,
            SimRecordCommand.self,
            SimOpenURLCommand.self,
            SimPushCommand.self,
            SimPrivacyCommand.self,
            SimAppearanceCommand.self,
            SimStatusBarCommand.self,
            SimLocationCommand.self,
            SimShutdownCommand.self,
        ]
    )
}

/// Default output paths for the capture commands.
enum SimPaths {
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func defaultPath(prefix: String, extension ext: String) -> String {
        "\(FileManager.default.currentDirectoryPath)/nimbus-\(prefix)-\(timestamp()).\(ext)"
    }

    /// Make a user-supplied path absolute, so what we report back is what was
    /// actually written regardless of where nimbus was run from.
    static func absolute(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return expanded
        }
        return "\(FileManager.default.currentDirectoryPath)/\(expanded)"
    }
}
