import ArgumentParser
import Foundation

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build, install, and launch on simulator"
    )

    @OptionGroup var options: SharedOptions

    mutating func run() throws {
        let config = try options.resolvedConfig()

        // Step 1: Build
        Console.step("Building \(config.scheme ?? "project")...")
        let runner = XcodeBuildRunner(config: config, verbose: options.verbose)
        let buildSuccess = try runner.execute(action: .build)
        guard buildSuccess else {
            throw ExitCode.failure
        }

        // Step 2: Find simulator
        let deviceName = config.device ?? "iPhone 17"
        Console.step("Finding simulator \"\(deviceName)\"...")

        guard let match = try SimulatorManager.findDevice(name: deviceName, os: config.os) else {
            Console.error("Simulator \"\(deviceName)\" not found. Run 'nimbus devices' to see available simulators.")
            throw ExitCode.failure
        }

        Console.verbose("Found: \(match.device.name) (\(match.device.udid))", isVerbose: options.verbose)

        // Step 3: Boot simulator
        Console.step("Booting simulator...")
        try SimulatorManager.boot(udid: match.device.udid)
        try SimulatorManager.openSimulatorApp()

        // Step 4: Find app bundle
        guard let scheme = config.scheme else {
            Console.error("Cannot determine scheme. Specify --scheme or add it to nimbus.yml.")
            throw ExitCode.failure
        }

        let configuration = config.configuration ?? "Debug"
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

        Console.step("Launching \(bundleID)...")
        try SimulatorManager.launch(udid: match.device.udid, bundleID: bundleID)

        Console.success("Running on \(match.device.name)")
    }
}
