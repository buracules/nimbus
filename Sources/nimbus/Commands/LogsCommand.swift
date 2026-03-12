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
        let match: (device: SimulatorManager.Device, runtime: String)

        if interactive {
            // Interactive device selection
            Console.step("Loading available simulators...")
            let groups = try SimulatorManager.listDevices()

            guard let selected = try DevicePicker.selectDevice(groups: groups, os: config.os) else {
                Console.info("No device selected")
                throw ExitCode.failure
            }
            match = selected
        } else {
            // Smart fallback device selection
            let requestedDevice = config.device
            let os = config.os

            if let requestedDevice = requestedDevice {
                Console.step("Finding simulator \"\(requestedDevice)\"...")
            } else {
                Console.step("Finding available simulator...")
            }

            guard let found = try SimulatorManager.findDeviceWithFallback(name: requestedDevice, os: os) else {
                Console.error("No simulators available. Run 'nimbus devices' to see available simulators.")
                throw ExitCode.failure
            }

            match = found

            // Show warning if we fell back to a different device
            if let requestedDevice = requestedDevice, match.device.name != requestedDevice {
                Console.warning("Device '\(requestedDevice)' not found, using '\(match.device.name)' instead")

                // Show fuzzy match suggestions
                let suggestions = try SimulatorManager.suggestDevices(for: requestedDevice, os: os)
                if !suggestions.isEmpty {
                    print("  Did you mean: \(suggestions.map { "\"\($0)\"" }.joined(separator: ", "))?")
                }
            } else if requestedDevice == nil {
                // No device specified, show which one we picked
                Console.info("Using device: \(match.device.name)")
            }
        }

        Console.verbose("Selected: \(match.device.name) (\(match.device.udid))", isVerbose: options.verbose)

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
