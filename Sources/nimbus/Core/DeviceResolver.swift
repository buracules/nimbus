import ArgumentParser
import Foundation

/// Resolves which simulator a command should target, via interactive picker
/// or smart fallback matching. Shared by run/logs/test.
enum DeviceResolver {
    /// Resolve a device either interactively or via smart fallback, printing
    /// the same status/warning/suggestion messages the commands have always shown.
    ///
    /// - Returns: The selected device and its runtime, or nil if the user
    ///   cancelled an interactive selection or no simulators are available
    ///   (in both cases an error/info message has already been printed).
    static func resolve(
        config: NimbusConfig,
        interactive: Bool,
        verbose: Bool
    ) throws -> (device: SimulatorManager.Device, runtime: String)? {
        guard let match = try select(config: config, interactive: interactive) else {
            return nil
        }
        Console.verbose("Selected: \(match.device.name) (\(match.device.udid))", isVerbose: verbose)
        return match
    }

    private static func select(
        config: NimbusConfig,
        interactive: Bool
    ) throws -> (device: SimulatorManager.Device, runtime: String)? {
        if interactive {
            Console.step("Loading available simulators...")
            let groups = try SimulatorManager.listDevices()

            guard let selected = try DevicePicker.selectDevice(groups: groups, os: config.os) else {
                Console.info("No device selected")
                return nil
            }
            return selected
        }

        let requestedDevice = config.device
        let os = config.os

        if let requestedDevice = requestedDevice {
            Console.step("Finding simulator \"\(requestedDevice)\"...")
        } else {
            Console.step("Finding available simulator...")
        }

        guard let found = try SimulatorManager.findDeviceWithFallback(name: requestedDevice, os: os) else {
            Console.error("No simulators available. Run 'nimbus devices' to see available simulators.")
            return nil
        }

        if let requestedDevice = requestedDevice, found.device.name != requestedDevice {
            Console.warning("Device '\(requestedDevice)' not found, using '\(found.device.name)' instead")

            let suggestions = try SimulatorManager.suggestDevices(for: requestedDevice, os: os)
            if !suggestions.isEmpty {
                print("  Did you mean: \(suggestions.map { "\"\($0)\"" }.joined(separator: ", "))?")
            }
        } else if requestedDevice == nil {
            Console.info("Using device: \(found.device.name)")
        } else {
            Console.info("Found: \(found.device.name)")
        }

        return found
    }
}
