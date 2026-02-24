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
        let groups = try SimulatorManager.listDevices()

        if groups.isEmpty {
            Console.warning("No simulators found. Open Xcode to install simulator runtimes.")
            return
        }

        for group in groups {
            let runtimeName = formatRuntime(group.runtime)
            print(Console.colored("\n\(runtimeName)", .bold))

            for device in group.devices {
                let status: String
                if device.isBooted {
                    status = Console.colored("(Booted)", .green)
                } else {
                    status = Console.colored("(Shutdown)", .dim)
                }
                print("  \(device.name) \(status)")
            }
        }
        print()
    }

    /// Convert runtime identifier like "com.apple.CoreSimulator.SimRuntime.iOS-18-0"
    /// to a human-readable name like "iOS 18.0".
    private func formatRuntime(_ identifier: String) -> String {
        // The identifier often looks like:
        // com.apple.CoreSimulator.SimRuntime.iOS-18-0
        let parts = identifier.split(separator: ".")
        guard let last = parts.last else { return identifier }
        return String(last).replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "iOS ", with: "iOS ")
            // Fix version: "iOS 18 0" -> "iOS 18.0"
            .replacing(#/(\d+) (\d+)$/#) { match in
                "\(match.1).\(match.2)"
            }
    }
}
