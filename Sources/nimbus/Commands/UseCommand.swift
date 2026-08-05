import ArgumentParser
import Foundation

/// Pins a simulator to the current project, and reports what is pinned.
///
/// This verb exists so that consumers without a working directory — a menu bar
/// app, an Alfred workflow — can answer "which simulator" by running nimbus and
/// parsing the envelope, instead of reading nimbus's own state file. The file is
/// private; this command is the contract.
struct UseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "Pin a simulator to this project, or show which one is in effect",
        discussion: """
        With a device name, resolves it against the simulators on this machine \
        and remembers it for this project. With no arguments, reports the \
        simulator currently in effect and which layer supplied it.

        A pinned simulator outranks this project's nimbus.yml but is still \
        overridden by --device on an individual command.
        """
    )

    @Argument(help: "Simulator device name to pin to this project")
    var device: String?

    @Option(name: .long, help: "Simulator OS version to pin alongside the device")
    var os: String?

    @Flag(name: .long, help: "Forget this project's pinned simulator")
    var clear = false

    @Flag(name: .long, help: "Show verbose output")
    var verbose = false

    @Flag(name: .long, help: "Emit a JSON result envelope on stdout instead of human output")
    var json = false

    mutating func run() throws {
        let device = self.device
        let os = self.os
        let clear = self.clear
        let verbose = self.verbose
        let json = self.json

        try CommandRunner.run("use", json: json) {
            if clear {
                guard device == nil, os == nil else {
                    throw NimbusFailure(
                        .invalidArguments,
                        "--clear takes no device name and no --os. Run 'nimbus use --clear' on its own."
                    )
                }
                return try Self.forget(verbose: verbose)
            }
            if let device {
                return try Self.pin(device: device, os: os, verbose: verbose, json: json)
            }
            return try Self.report(verbose: verbose)
        }
    }

    // MARK: - Pin

    /// Resolve the requested name, then persist it only if it matched.
    ///
    /// Persisting an unresolvable name would reproduce the failure this whole
    /// feature is meant to prevent: a config naming a simulator that does not
    /// exist, discovered a minute into a build. `use` is the one place to catch
    /// that at the source, and routing through `DeviceSelection` gives a typo
    /// the same fuzzy suggestions as every other command.
    private static func pin(device: String, os: String?, verbose: Bool, json: Bool) throws -> UsePayload {
        let resolution = try SelectionChain.resolve(cli: NimbusConfig(device: device, os: os))
        resolution.narrateLayers(verbose: verbose)

        let choice = try DeviceSelection.choose(
            config: resolution.config,
            interactive: false,
            verbose: verbose,
            json: json
        )

        guard let matched = choice.resolution, matched.matchedRequest else {
            var diagnostics: [String] = []
            if let suggestions = choice.resolution?.suggestions, !suggestions.isEmpty {
                diagnostics.append(
                    "Did you mean: " + suggestions.map { "\"\($0)\"" }.joined(separator: ", ") + "?"
                )
            }
            throw NimbusFailure(
                .notFound,
                "No simulator named '\(device)' on this machine. Nothing was pinned.",
                diagnostics: diagnostics
            )
        }

        // The device name is stored, never the UDID — see `StoredSelection`.
        // Only the `--os` given here is stored: a version inherited from global
        // or project config is that layer's preference, and freezing it into
        // this project's state would make it stop tracking the layer it came
        // from.
        let selection = StoredSelection(
            projectRoot: resolution.projectRoot,
            device: matched.device.name,
            os: os
        )
        try SelectionStore.save(selection)

        Console.success(
            "Pinned \(selection.device)"
                + (selection.os.map { " (OS \($0))" } ?? "")
                + " to \(selection.projectRoot)"
        )

        return UsePayload(
            projectRoot: selection.projectRoot,
            device: selection.device,
            os: selection.os,
            source: .state,
            shadowedProjectDevice: nil,
            resolution: matched,
            cleared: false
        )
    }

    // MARK: - Clear

    private static func forget(verbose: Bool) throws -> UsePayload {
        let projectRoot = ProjectIdentity.projectRoot()
        let removed = try SelectionStore.clear(projectRoot: projectRoot)

        if removed {
            Console.success("Unpinned the simulator for \(projectRoot)")
        } else {
            Console.info("No simulator was pinned to \(projectRoot)")
        }

        // Report what applies now, so the user sees the layer that takes over
        // rather than being left to guess.
        var payload = try effective(verbose: verbose)
        payload.cleared = removed
        return payload
    }

    // MARK: - Report

    private static func report(verbose: Bool) throws -> UsePayload {
        let payload = try effective(verbose: verbose)
        render(payload)
        return payload
    }

    /// The device currently in effect for this project, matched against the
    /// simulators that exist.
    private static func effective(verbose: Bool) throws -> UsePayload {
        let resolution = try SelectionChain.resolve(cli: .empty)
        resolution.narrateLayers(verbose: verbose)

        // Resolved directly rather than through `DeviceSelection.choose`: this
        // command reports, so "Finding simulator..." would be the wrong
        // narration, and a machine with no simulators must still get an answer
        // about its configuration instead of a failure.
        let matched = try DeviceResolver.resolveDevice(config: resolution.config)

        return UsePayload(
            projectRoot: resolution.projectRoot,
            device: resolution.config.device,
            os: resolution.config.os,
            source: resolution.deviceSource,
            shadowedProjectDevice: resolution.shadowedProjectDevice,
            resolution: matched,
            cleared: false
        )
    }

    private static func render(_ payload: UsePayload) {
        guard !Console.isMachineReadable else { return }

        Console.info("Project: \(payload.projectRoot)")

        if let device = payload.device {
            Console.info("Device: \(device) — from \(SelectionChain.describe(payload.source))")
        } else {
            Console.info("Device: not pinned or configured — nimbus picks an available simulator")
        }
        if let os = payload.os {
            Console.info("OS: \(os)")
        }
        if let shadowed = payload.shadowedProjectDevice {
            Console.warning("nimbus.yml's device '\(shadowed)' is not in effect here")
        }

        guard let resolution = payload.resolution else {
            Console.warning("No simulators available on this machine")
            return
        }
        let state = resolution.device.isBooted ? "Booted" : "Shutdown"
        Console.info(
            "Simulator: \(resolution.device.name) — "
                + "\(SimulatorManager.runtimeDisplayName(resolution.runtime)) (\(state))"
        )
        if !resolution.matchedRequest, let requested = resolution.requestedName {
            Console.warning("'\(requested)' does not exist here; '\(resolution.device.name)' would be used instead")
        }
    }
}
