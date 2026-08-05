import ArgumentParser
import Foundation

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List available simulators"
    )

    @Flag(name: .long, help: "Show all devices including unavailable ones")
    var all = false

    @Flag(name: .long, help: "Emit a JSON result envelope on stdout instead of human output")
    var json = false

    mutating func run() throws {
        let all = self.all
        let json = self.json

        try CommandRunner.run("devices", json: json) {
            try Self.perform(all: all)
        }
    }

    private static func perform(all: Bool) throws -> DevicesPayload {
        let groups = try SimulatorManager.listDevices(includeUnavailable: all)

        let payload = DevicesPayload(
            runtimes: groups.map { group in
                DevicesPayload.RuntimeGroup(
                    runtime: group.runtime,
                    name: SimulatorManager.runtimeDisplayName(group.runtime),
                    devices: group.devices
                )
            }
        )

        // The human listing is a rendering of exactly the same payload, so the
        // two views cannot disagree about what was found.
        if !Console.isMachineReadable {
            render(payload)
        }
        return payload
    }

    private static func render(_ payload: DevicesPayload) {
        guard !payload.runtimes.isEmpty else {
            Console.warning("No simulators found. Open Xcode to install simulator runtimes.")
            return
        }

        for group in payload.runtimes {
            Console.detail(Console.colored("\n\(group.name)", .bold))
            for device in group.devices {
                Console.detail("  \(device.name) \(statusBadge(for: device))")
            }
        }
        Console.detail()
    }

    private static func statusBadge(for device: SimulatorManager.Device) -> String {
        if !device.isAvailable {
            var badge = Console.colored("(Unavailable)", .dim)
            if let reason = device.availabilityError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                badge += " " + Console.colored(reason, .dim)
            }
            return badge
        }
        if device.isBooted {
            return Console.colored("(Booted)", .green)
        }
        return Console.colored("(Shutdown)", .dim)
    }
}
