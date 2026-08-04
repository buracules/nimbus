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

        // Step 3: Determine bundle ID
        let appBundleID: String
        if let providedBundleID = bundleID {
            appBundleID = providedBundleID
        } else {
            // Auto-detect from scheme
            guard let scheme = config.scheme else {
                Console.error("Cannot determine bundle ID. Specify --bundle-id or --scheme.")
                throw ExitCode.failure
            }

            let configuration = config.configuration ?? "Debug"
            guard let appPath = SimulatorManager.findAppBundle(scheme: scheme, configuration: configuration) else {
                Console.error("Built app not found in DerivedData. Build the app first with 'nimbus run' or 'nimbus build'.")
                throw ExitCode.failure
            }

            guard let bundleID = SimulatorManager.bundleIdentifier(appPath: appPath) else {
                Console.error("Could not determine bundle identifier from app at \(appPath)")
                throw ExitCode.failure
            }

            appBundleID = bundleID
        }

        // Step 4: Stream logs
        Console.step("Streaming logs for \(appBundleID) on \(match.device.name)...")
        Console.info("Press Ctrl+C to stop")
        print()

        let exitCode = try ProcessRunner.stream(
            "/usr/bin/xcrun",
            arguments: [
                "simctl", "spawn", match.device.udid,
                "log", "stream",
                "--predicate", "processImagePath CONTAINS \"\(appBundleID)\"",
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
}
