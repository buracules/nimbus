import ArgumentParser
import Foundation

/// The device a command ended up with, and how it got there.
struct DeviceChoice {
    let device: SimulatorManager.Device
    let runtime: String
    /// How core matched the configured device. Nil when a human picked from
    /// the menu instead, in which case there was no matching to report.
    let resolution: DeviceResolution?
}

/// CLI-side device choice: ask the human when `--interactive`, otherwise let
/// core match, then say what happened.
///
/// Core decides *which* simulator. This decides what the user is told about it,
/// which is why it lives next to the commands and is allowed to print.
enum DeviceSelection {
    static func choose(
        config: NimbusConfig,
        interactive: Bool,
        verbose: Bool,
        json: Bool = false,
        shadowedProjectDevice: String? = nil
    ) throws -> DeviceChoice {
        // A menu prompt and an envelope cannot share stdout, and there is no
        // one on the other end of `--json` to answer a prompt anyway. So
        // `--json` means "match, never ask" — and says so rather than
        // silently ignoring the flag the caller passed.
        let ask = interactive && !json
        if interactive && json {
            Console.warning("--interactive is ignored with --json; matching a simulator instead")
        }

        // A pinned selection outranks the project's `nimbus.yml`, so a committed
        // `device:` can stop taking effect without the file changing. That is
        // invisible unless it is said out loud, and it is said at normal
        // verbosity because a user who does not know to pass `--verbose` is
        // exactly the one it surprises. Not shown for the interactive menu:
        // there, the human picked and neither layer supplied anything.
        if !ask, let shadowed = shadowedProjectDevice, let inEffect = config.device {
            Console.info(
                "Using '\(inEffect)' pinned by 'nimbus use' — nimbus.yml's device "
                    + "'\(shadowed)' is not in effect here (clear it with 'nimbus use --clear')"
            )
        }

        let choice = ask ? try pick(config: config) : try match(config: config)
        Console.verbose(
            "Selected: \(choice.device.name) (\(choice.device.udid))",
            isVerbose: verbose
        )
        return choice
    }

    // MARK: - Interactive

    private static func pick(config: NimbusConfig) throws -> DeviceChoice {
        Console.step("Loading available simulators...")
        // A human is waiting, so the authoritative-but-slower listing is fine
        // here, and it is the one that reports availability.
        let groups = try SimulatorManager.listDevices()

        guard let selected = try DevicePicker.selectDevice(groups: groups, os: config.os) else {
            throw NimbusFailure(.noDeviceSelected, "No device selected")
        }
        return DeviceChoice(device: selected.device, runtime: selected.runtime, resolution: nil)
    }

    // MARK: - Matched

    private static func match(config: NimbusConfig) throws -> DeviceChoice {
        if let requested = config.device {
            Console.step("Finding simulator \"\(requested)\"...")
        } else {
            Console.step("Finding available simulator...")
        }

        guard let resolution = try DeviceResolver.resolveDevice(config: config) else {
            throw NimbusFailure(
                .noSimulators,
                "No simulators available. Run 'nimbus devices' to see available simulators."
            )
        }

        narrate(resolution)
        return DeviceChoice(
            device: resolution.device,
            runtime: resolution.runtime,
            resolution: resolution
        )
    }

    /// Turn a resolution into the lines the user reads.
    static func narrate(_ resolution: DeviceResolution) {
        guard let requested = resolution.requestedName else {
            Console.info("Using device: \(resolution.device.name)")
            return
        }

        guard resolution.matchedRequest else {
            Console.warning("Device '\(requested)' not found, using '\(resolution.device.name)' instead")
            if !resolution.suggestions.isEmpty {
                let names = resolution.suggestions.map { "\"\($0)\"" }.joined(separator: ", ")
                Console.detail("  Did you mean: \(names)?")
            }
            return
        }

        Console.info("Found: \(resolution.device.name)")
    }
}
