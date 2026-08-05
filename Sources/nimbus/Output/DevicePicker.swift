import Foundation

/// Interactive device picker for selecting simulators from a menu
enum DevicePicker {
    /// Display an interactive menu for device selection.
    ///
    /// - Parameters:
    ///   - groups: Array of (runtime, devices) tuples to display
    ///   - os: Optional OS filter being applied (for display purposes)
    /// - Returns: Selected (device, runtime) tuple, or nil if user cancels
    static func selectDevice(
        groups: [(runtime: String, devices: [SimulatorManager.Device])],
        os: String? = nil
    ) throws -> (device: SimulatorManager.Device, runtime: String)? {
        // The menu writes a prompt to stdout and blocks on stdin. Under
        // `--json` stdout belongs to the envelope and there is nobody to
        // answer, so refuse here rather than trust every caller to remember.
        // `DeviceSelection` already downgrades `--interactive` to matching, so
        // reaching this is a bug, not a user error.
        guard !Console.isMachineReadable else {
            throw NimbusFailure(
                .unsupportedOutputMode,
                "Interactive device selection cannot run with --json."
            )
        }

        guard !groups.isEmpty else {
            Console.error("No simulators available")
            return nil
        }

        // Build a flat list of devices with their runtime info
        var deviceList: [(device: SimulatorManager.Device, runtime: String)] = []
        for group in groups {
            for device in group.devices {
                deviceList.append((device: device, runtime: group.runtime))
            }
        }

        guard !deviceList.isEmpty else {
            Console.error("No simulators available")
            return nil
        }

        // Display header
        print()
        if let os = os {
            Console.step("Select a simulator (OS: \(os)):")
        } else {
            Console.step("Select a simulator:")
        }
        print()

        // Display numbered list of devices
        for (index, item) in deviceList.enumerated() {
            let number = Console.colored("\(index + 1).", .cyan)
            let deviceName = Console.colored(item.device.name, .bold)
            let statusBadge = item.device.isBooted
                ? Console.colored(" [Booted]", .green)
                : ""
            let runtime = Console.colored("(\(item.runtime))", .dim)

            print("  \(number) \(deviceName)\(statusBadge) \(runtime)")
        }

        print()
        print("  \(Console.colored("q", .cyan)). Cancel")
        print()

        // Read user input
        while true {
            print("Enter selection: ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                return nil
            }

            // Handle quit
            if input.lowercased() == "q" {
                Console.info("Selection cancelled")
                return nil
            }

            // Try to parse as number
            guard let selection = Int(input), selection >= 1, selection <= deviceList.count else {
                Console.warning("Invalid selection. Please enter a number from 1 to \(deviceList.count), or 'q' to cancel.")
                continue
            }

            // Return selected device
            let selectedItem = deviceList[selection - 1]
            print()
            Console.success("Selected: \(selectedItem.device.name)")
            return selectedItem
        }
    }
}
