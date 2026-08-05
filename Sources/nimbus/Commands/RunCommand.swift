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
        let options = self.options
        let interactive = self.interactive
        let logs = self.logs

        try CommandRunner.run("run", json: options.json) {
            try Self.perform(options: options, interactive: interactive, logs: logs)
        }
    }

    private static func perform(
        options: SharedOptions,
        interactive: Bool,
        logs: Bool
    ) throws -> RunPayload {
        // A console stream and a result envelope both want stdout, and only one
        // of them can have it. Refuse before doing any work rather than build
        // the app and then discover the output mode is impossible.
        if logs && options.json {
            throw NimbusFailure(
                .unsupportedOutputMode,
                "--json cannot be combined with --logs: a console stream and a JSON envelope "
                    + "cannot share stdout. Run 'nimbus run --json' to build and launch, then "
                    + "'nimbus logs' separately."
            )
        }

        let selection = try options.resolvedSelection()
        let config = selection.config

        // Step 1: Find simulator (interactive or fallback)
        let choice = try DeviceSelection.choose(
            config: config,
            interactive: interactive,
            verbose: options.verbose,
            json: options.json,
            shadowedProjectDevice: selection.shadowedProjectDevice
        )
        let device = choice.device

        // Step 2: Build using the simulator UDID for a reliable destination match
        Console.step("Building \(config.scheme ?? "project")...")
        let runner = XcodeBuildRunner(config: config, destinationUDID: device.udid)
        let execution = try BuildExecutor.execute(action: .build, runner: runner, verbose: options.verbose)
        guard execution.result.succeeded else {
            throw BuildExecutor.failure(.buildFailed, "Build failed", from: execution)
        }

        // Step 3: Boot simulator
        Console.step("Booting simulator...")
        try SimulatorManager.boot(udid: device.udid)
        try SimulatorManager.openSimulatorApp()
        Console.info("Simulator ready")

        // Step 4: Find app bundle
        guard config.scheme != nil else {
            throw NimbusFailure(
                .schemeUnknown,
                "Cannot determine scheme. Specify --scheme or add it to nimbus.yml."
            )
        }

        Console.step("Locating app bundle...")
        guard let appPath = BuildExecutor.locateAppBundle(runner: runner, verbose: options.verbose) else {
            throw NimbusFailure(.appBundleNotFound, "Built app not found. Try a clean build.")
        }

        Console.verbose("App path: \(appPath)", isVerbose: options.verbose)

        // Step 5: Install
        Console.step("Installing on \(device.name)...")
        try SimulatorManager.install(udid: device.udid, appPath: appPath)

        // Step 6: Launch
        guard let bundleID = SimulatorManager.bundleIdentifier(appPath: appPath) else {
            throw NimbusFailure(
                .bundleIdentifierUnknown,
                "Could not determine bundle identifier from app at \(appPath)"
            )
        }

        // Step 7: Launch with console capture if logs requested
        if logs {
            try launchWithConsole(device: device, bundleID: bundleID)
        } else {
            Console.step("Launching \(bundleID)...")
            try SimulatorManager.launch(udid: device.udid, bundleID: bundleID)
            Console.success("Running on \(device.name)")
        }

        return RunPayload(
            scheme: config.scheme,
            configuration: config.configuration,
            resolution: choice.resolution,
            build: execution.result,
            app: RunPayload.App(path: appPath, bundleID: bundleID)
        )
    }

    /// Launch and hold the terminal until the app's console output ends.
    /// Never reached under `--json`, which refuses this combination up front.
    private static func launchWithConsole(
        device: SimulatorManager.Device,
        bundleID: String
    ) throws {
        Console.step("Launching \(bundleID) with console output...")
        Console.info("Press Ctrl+C to stop")
        Console.detail()

        // Terminate existing instance first
        _ = try? ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "terminate", device.udid, bundleID]
        )

        // Launch with console output
        let exitCode = try ProcessRunner.stream(
            "/usr/bin/xcrun",
            arguments: [
                "simctl", "launch",
                "--console-pty",
                device.udid,
                bundleID
            ],
            onStdout: { line in
                print(line)
            },
            onStderr: { line in
                print(line)
            }
        )

        // exit code 2 = user interrupted
        if exitCode != 0 && exitCode != 2 {
            throw NimbusFailure(
                .commandFailed,
                "simctl launch --console-pty exited with \(exitCode)",
                exitCode: exitCode
            )
        }
    }
}
