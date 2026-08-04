import ArgumentParser
import Foundation

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Stream app logs from simulator"
    )

    @OptionGroup var options: SharedOptions
    @Option(name: .long, help: "Bundle identifier of the app to stream logs for") var bundleID: String?
    @Flag(name: .long, help: "Interactively select a simulator") var interactive = false

    mutating func run() throws {
        let config = try options.resolvedConfig()

        // Step 1: Find simulator (interactive or fallback)
        guard let match = try DeviceResolver.resolve(config: config, interactive: interactive, verbose: options.verbose) else {
            throw ExitCode.failure
        }

        // Step 2: Boot simulator if needed
        if !match.device.isBooted {
            Console.step("Booting simulator...")
            try SimulatorManager.boot(udid: match.device.udid)
            try SimulatorManager.openSimulatorApp()
            // Give the simulator a moment to fully boot
            Thread.sleep(forTimeInterval: 2.0)
        }

        // Step 3: Determine bundle ID and the process name to match on
        let appBundleID: String
        let executableName: String?
        if let providedBundleID = bundleID {
            appBundleID = providedBundleID
            // No app bundle to read CFBundleExecutable from — best effort.
            executableName = Self.processName(fromBundleID: providedBundleID)
        } else {
            // Auto-detect from scheme
            guard config.scheme != nil else {
                Console.error("Cannot determine bundle ID. Specify --bundle-id or --scheme.")
                throw ExitCode.failure
            }

            let runner = XcodeBuildRunner(
                config: config,
                verbose: options.verbose,
                destinationUDID: match.device.udid
            )
            guard let appPath = runner.locateAppBundle() else {
                Console.error("Built app not found. Build the app first with 'nimbus run' or 'nimbus build'.")
                throw ExitCode.failure
            }

            guard let bundleID = SimulatorManager.bundleIdentifier(appPath: appPath) else {
                Console.error("Could not determine bundle identifier from app at \(appPath)")
                throw ExitCode.failure
            }

            appBundleID = bundleID
            executableName = SimulatorManager.executableName(appPath: appPath)
                ?? Self.processName(fromBundleID: bundleID)
        }

        // Step 4: Stream logs
        let predicate = Self.buildPredicate(executableName: executableName, bundleID: appBundleID)
        Console.verbose("Predicate: \(predicate)", isVerbose: options.verbose)

        Console.step("Streaming logs for \(appBundleID) on \(match.device.name)...")
        Console.info("Press Ctrl+C to stop")
        print()

        let exitCode = try ProcessRunner.stream(
            "/usr/bin/xcrun",
            arguments: [
                "simctl", "spawn", match.device.udid,
                "log", "stream",
                "--predicate", predicate,
                "--style", "compact"
            ],
            onStdout: { line in
                print(line)
            },
            onStderr: { line in
                var stderr = FileHandle.standardError
                print(line, to: &stderr)
            }
        )

        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }

    // MARK: - Predicate

    /// Build the `log stream` predicate for an app.
    ///
    /// Two clauses, OR'd: the process image path catches print/stderr output
    /// (on a simulator that path ends in `.../MyApp.app/MyApp`, which never
    /// contains the bundle identifier), and the subsystem catches `os.Logger`
    /// output.
    static func buildPredicate(executableName: String?, bundleID: String) -> String {
        var clauses: [String] = []
        if let executableName, !executableName.isEmpty {
            clauses.append("processImagePath ENDSWITH \"/\(escape(executableName))\"")
        }
        clauses.append("subsystem == \"\(escape(bundleID))\"")
        return clauses.joined(separator: " OR ")
    }

    /// Best-effort process name for a bundle identifier: the last dot-component
    /// of `com.example.MyApp` is usually the executable name.
    static func processName(fromBundleID bundleID: String) -> String? {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.isEmpty ? nil : last
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
