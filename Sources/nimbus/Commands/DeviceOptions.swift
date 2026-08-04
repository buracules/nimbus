import ArgumentParser
import Foundation

/// The flags that pick a simulator, for commands that only need a simulator.
///
/// Deliberately not `SharedOptions`: that one auto-detects a scheme when none
/// is configured, which costs an `xcodebuild -list`. None of the `sim`
/// commands build anything, and they are supposed to feel instant.
struct DeviceOptions: ParsableArguments {
    @Option(name: .long, help: "Simulator device name")
    var device: String?

    @Option(name: .long, help: "Simulator OS version")
    var os: String?

    @Flag(name: .long, help: "Interactively select a simulator")
    var interactive = false

    @Flag(name: .long, help: "Show verbose output")
    var verbose = false

    /// Config for device selection only: global < project < CLI flags, with no
    /// scheme detection.
    func resolvedConfig() throws -> NimbusConfig {
        let globalConfig = try ConfigLoader.loadGlobal()
        let projectConfig = try ConfigLoader.loadProject()
        let cliConfig = NimbusConfig(device: device, os: os)
        return globalConfig.merging(with: projectConfig).merging(with: cliConfig)
    }

    /// Resolve the simulator this command targets.
    func selectDevice() throws -> DeviceChoice {
        try DeviceSelection.choose(
            config: try resolvedConfig(),
            interactive: interactive,
            verbose: verbose
        )
    }

    /// Resolve the simulator, booting it if it does not look booted already.
    ///
    /// Most `simctl` operations require a booted device. The reported state is
    /// a hint that lags an in-flight transition, and confirming it costs
    /// `simctl boot` plus `bootstatus` — 0.45 s, a third of the wall time of a
    /// screenshot. So when the hint says booted, take it: if it was stale
    /// because a shutdown was in flight, simctl says so plainly and the retry
    /// costs less than paying the check on every invocation. When the hint says
    /// anything else, boot properly, which is the right action either way.
    ///
    /// `nimbus logs` makes the opposite call and always confirms — it streams
    /// for minutes, so the check rounds to nothing there.
    func selectBootedDevice() throws -> DeviceChoice {
        let choice = try selectDevice()
        guard !choice.device.isBooted else { return choice }

        Console.step("Booting \(choice.device.name)...")
        try SimulatorManager.boot(udid: choice.device.udid)
        return choice
    }
}
