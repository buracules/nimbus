import Foundation

/// The `xcrun simctl` operations behind `nimbus sim`.
///
/// Every call here returns what happened or throws. Nothing prints: what the
/// user is told is the caller's business.
enum SimulatorControl {

    // MARK: - Result values

    /// A file one of these operations wrote.
    struct CapturedFile: Codable, Equatable {
        let path: String
    }

    /// One device's outcome from a shutdown request.
    struct ShutdownOutcome: Codable, Equatable {
        let udid: String
        let name: String
        /// False when the device was already shut down and nothing was done.
        let wasBooted: Bool
    }

    enum PrivacyAction: String, Codable, CaseIterable {
        case grant, revoke, reset
    }

    enum Appearance: String, Codable, CaseIterable {
        case light, dark
    }

    // MARK: - Capture

    /// Save a screenshot of the device's display.
    @discardableResult
    static func screenshot(udid: String, path: String, type: String? = nil) throws -> CapturedFile {
        var args = ["simctl", "io", udid, "screenshot"]
        if let type {
            args.append("--type=\(type)")
        }
        args.append(path)
        try runSimctl(args, describedAs: "simctl io screenshot")
        return CapturedFile(path: path)
    }

    /// A screen recording that is currently running.
    ///
    /// The movie only exists once the recording has been *stopped*: simctl
    /// finalizes and writes the file when it is interrupted, and writes a
    /// zero-byte file when it is terminated (measured: interrupt gives a valid
    /// movie and exit 0, terminate gives 0 bytes and exit 143). So stopping is
    /// `stop()` — not killing whatever process started the recording.
    ///
    /// The CLI maps Ctrl+C onto `stop()`. A GUI would map a button onto it.
    final class Recording {
        let path: String
        private let handle: ProcessRunner.Handle

        fileprivate init(path: String, handle: ProcessRunner.Handle) {
            self.path = path
            self.handle = handle
        }

        var isRecording: Bool { handle.isRunning }

        /// Ask simctl to stop recording and write the movie.
        func stop() {
            handle.interrupt()
        }

        /// Block until the movie has been written. Returns simctl's exit code.
        @discardableResult
        func waitUntilFinished() -> Int32 {
            handle.wait()
        }
    }

    /// Start recording the device's display. The caller stops it.
    static func startRecording(
        udid: String,
        path: String,
        codec: String? = nil,
        onOutputLine: @escaping (String) -> Void = { _ in }
    ) throws -> Recording {
        var args = ["simctl", "io", udid, "recordVideo"]
        if let codec {
            args.append("--codec=\(codec)")
        }
        args.append(path)

        let handle = try ProcessRunner.start(xcrun, arguments: args, onStdout: onOutputLine)
        return Recording(path: path, handle: handle)
    }

    // MARK: - Interaction

    static func openURL(udid: String, url: String) throws {
        try runSimctl(["simctl", "openurl", udid, url], describedAs: "simctl openurl")
    }

    static func push(udid: String, bundleID: String?, payloadPath: String) throws {
        var args = ["simctl", "push", udid]
        if let bundleID {
            args.append(bundleID)
        }
        args.append(payloadPath)
        try runSimctl(args, describedAs: "simctl push")
    }

    static func privacy(
        udid: String,
        action: PrivacyAction,
        service: String,
        bundleID: String?
    ) throws {
        var args = ["simctl", "privacy", udid, action.rawValue, service]
        if let bundleID {
            args.append(bundleID)
        }
        try runSimctl(args, describedAs: "simctl privacy")
    }

    // MARK: - Appearance and status bar

    static func setAppearance(udid: String, style: Appearance) throws {
        try runSimctl(["simctl", "ui", udid, "appearance", style.rawValue], describedAs: "simctl ui appearance")
    }

    /// The device's current appearance, as simctl reports it (`light`, `dark`,
    /// `unsupported` or `unknown`).
    static func currentAppearance(udid: String) throws -> String {
        try runSimctl(["simctl", "ui", udid, "appearance"], describedAs: "simctl ui appearance")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Apply status bar overrides. `overrides` are simctl's own flag pairs.
    static func overrideStatusBar(udid: String, overrides: [String]) throws {
        try runSimctl(["simctl", "status_bar", udid, "override"] + overrides, describedAs: "simctl status_bar override")
    }

    static func clearStatusBar(udid: String) throws {
        try runSimctl(["simctl", "status_bar", udid, "clear"], describedAs: "simctl status_bar clear")
    }

    // MARK: - Location

    static func setLocation(udid: String, latitude: Double, longitude: Double) throws {
        try runSimctl(
            ["simctl", "location", udid, "set", "\(latitude),\(longitude)"],
            describedAs: "simctl location set"
        )
    }

    static func clearLocation(udid: String) throws {
        try runSimctl(["simctl", "location", udid, "clear"], describedAs: "simctl location clear")
    }

    // MARK: - Lifecycle

    /// Shut a device down. Already-shut-down is not an error: simctl reports
    /// exit code 149 for it, which means the requested state already holds.
    static func shutdown(udid: String) throws {
        let result = try ProcessRunner.run(xcrun, arguments: ["simctl", "shutdown", udid])
        guard result.succeeded || result.exitCode == 149 else {
            throw NimbusError.commandFailed("simctl shutdown", result.stderr)
        }
    }

    // MARK: - Plumbing

    private static let xcrun = "/usr/bin/xcrun"

    @discardableResult
    private static func runSimctl(_ arguments: [String], describedAs description: String) throws -> String {
        let result = try ProcessRunner.run(xcrun, arguments: arguments)
        guard result.succeeded else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NimbusError.commandFailed(description, message.isEmpty ? result.stdout : message)
        }
        return result.stdout
    }
}
