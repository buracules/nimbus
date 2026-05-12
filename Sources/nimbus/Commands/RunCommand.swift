import ArgumentParser
import Foundation

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build, install, and launch on simulator"
    )

    @OptionGroup var options: SharedOptions
    @Flag(name: .long, help: "Interactively select a simulator") var interactive = false
    @Flag(name: .long, help: "Stream console output (stdout/stderr) after launching") var logs = false

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

            // Show warning if we fell back to a different device
            if let requestedDevice = requestedDevice, found.device.name != requestedDevice {
                Console.warning("Device '\(requestedDevice)' not found, using '\(found.device.name)' instead")

                // Show fuzzy match suggestions
                let suggestions = try SimulatorManager.suggestDevices(for: requestedDevice, os: os)
                if !suggestions.isEmpty {
                    print("  Did you mean: \(suggestions.map { "\"\($0)\"" }.joined(separator: ", "))?")
                }
            } else if requestedDevice == nil {
                // No device specified, show which one we picked
                Console.info("Using device: \(found.device.name)")
            } else {
                // Exact match found
                Console.info("Found: \(found.device.name)")
            }

            match = found
        }

        Console.verbose("Selected: \(match.device.name) (\(match.device.udid))", isVerbose: options.verbose)

        // Step 2: Build using the simulator UDID for a reliable destination match
        Console.step("Building \(config.scheme ?? "project")...")
        let runner = XcodeBuildRunner(
            config: config,
            verbose: options.verbose,
            destinationUDID: match.device.udid
        )
        let buildSuccess = try runner.execute(action: .build)
        guard buildSuccess else {
            throw ExitCode.failure
        }

        // Step 3: Boot simulator
        Console.step("Booting simulator...")
        try SimulatorManager.boot(udid: match.device.udid)
        try SimulatorManager.openSimulatorApp()
        Console.info("Simulator ready")

        // Step 4: Find app bundle
        guard let scheme = config.scheme else {
            Console.error("Cannot determine scheme. Specify --scheme or add it to nimbus.yml.")
            throw ExitCode.failure
        }

        let configuration = config.configuration ?? "Debug"
        Console.step("Locating app bundle...")
        guard let appPath = SimulatorManager.findAppBundle(scheme: scheme, configuration: configuration) else {
            Console.error("Built app not found in DerivedData. Try a clean build.")
            throw ExitCode.failure
        }

        Console.verbose("App path: \(appPath)", isVerbose: options.verbose)

        // Step 5: Install
        Console.step("Installing on \(match.device.name)...")
        try SimulatorManager.install(udid: match.device.udid, appPath: appPath)

        // Step 6: Launch
        guard let bundleID = SimulatorManager.bundleIdentifier(appPath: appPath) else {
            Console.error("Could not determine bundle identifier from app.")
            throw ExitCode.failure
        }

        // Step 7: Launch with console capture if logs requested
        if logs {
            Console.step("Launching \(bundleID) with console output...")
            Console.info("Press Ctrl+C to stop")
            print()

            // Terminate existing instance first
            _ = try? ProcessRunner.run(
                "/usr/bin/xcrun",
                arguments: ["simctl", "terminate", match.device.udid, bundleID]
            )

            // Launch with console output
            let exitCode = try ProcessRunner.stream(
                "/usr/bin/xcrun",
                arguments: [
                    "simctl", "launch",
                    "--console-pty",
                    match.device.udid,
                    bundleID
                ],
                onStdout: { line in
                    print(line)
                },
                onStderr: { line in
                    print(line)
                }
            )

            if exitCode != 0 && exitCode != 2 { // exit code 2 = user interrupted
                throw ExitCode(exitCode)
            }
        } else {
            Console.step("Launching \(bundleID)...")
            try SimulatorManager.launch(udid: match.device.udid, bundleID: bundleID)
            Console.success("Running on \(match.device.name)")
        }
    }
}
