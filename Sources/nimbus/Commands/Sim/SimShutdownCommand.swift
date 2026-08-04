import ArgumentParser
import Foundation

struct SimShutdownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shutdown",
        abstract: "Shut down a simulator, or every booted one"
    )

    @OptionGroup var options: DeviceOptions

    @Flag(name: .long, help: "Shut down every booted simulator")
    var all = false

    mutating func run() throws {
        let outcomes = all ? try shutdownAll() : try shutdownResolved()

        let stopped = outcomes.filter(\.wasBooted)
        guard !stopped.isEmpty else {
            Console.info("Nothing to shut down — no booted simulators")
            return
        }
        for outcome in stopped {
            Console.success("Shut down \(outcome.name)")
        }
    }

    private func shutdownAll() throws -> [SimulatorControl.ShutdownOutcome] {
        // Which devices are booted is exactly the thing the fast index reports
        // late, and shutting the wrong set down is not recoverable by
        // retrying, so ask the authority.
        let groups = try SimulatorManager.listDevices()
        let booted = groups.flatMap { $0.devices }.filter(\.isBooted)

        return try booted.map { device in
            Console.step("Shutting down \(device.name)...")
            try SimulatorControl.shutdown(udid: device.udid)
            return SimulatorControl.ShutdownOutcome(udid: device.udid, name: device.name, wasBooted: true)
        }
    }

    private func shutdownResolved() throws -> [SimulatorControl.ShutdownOutcome] {
        // Never boot something on the way to shutting it down.
        let choice = try options.selectDevice()
        let device = choice.device

        Console.step("Shutting down \(device.name)...")
        try SimulatorControl.shutdown(udid: device.udid)

        // The state we hold is a hint, so report on what we asked for rather
        // than claiming to know what it was.
        return [SimulatorControl.ShutdownOutcome(udid: device.udid, name: device.name, wasBooted: true)]
    }
}
