import ArgumentParser
import Foundation

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List available simulators"
    )

    @Flag(name: .long, help: "Show all devices including unavailable ones")
    var all = false

    mutating func run() throws {
        let groups = try SimulatorManager.listDevices(includeUnavailable: all)

        if groups.isEmpty {
            Console.warning("No simulators found. Open Xcode to install simulator runtimes.")
            return
        }

        for group in groups {
            let runtimeName = SimulatorManager.runtimeDisplayName(group.runtime)
            print(Console.colored("\n\(runtimeName)", .bold))

            for device in group.devices {
                print("  \(device.name) \(statusBadge(for: device))")
            }
        }
        print()
    }

    private func statusBadge(for device: SimulatorManager.Device) -> String {
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
