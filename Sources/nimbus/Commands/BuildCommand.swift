import ArgumentParser
import Foundation

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the project"
    )

    @OptionGroup var options: SharedOptions
    @Flag(name: .long, help: "Interactively select a simulator") var interactive = false

    mutating func run() throws {
        let options = self.options
        let interactive = self.interactive

        try CommandRunner.run("build", json: options.json) {
            try Self.perform(options: options, interactive: interactive)
        }
    }

    private static func perform(options: SharedOptions, interactive: Bool) throws -> BuildPayload {
        let config = try options.resolvedConfig()

        // Resolve a concrete simulator like run/test do. Without this the
        // destination is `name=<configured device>` verbatim, which fails
        // whenever the configured name does not exist on this machine.
        let choice = try DeviceSelection.choose(
            config: config,
            interactive: interactive,
            verbose: options.verbose,
            json: options.json
        )

        Console.step("Building \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, destinationUDID: choice.device.udid)
        let execution = try BuildExecutor.execute(action: .build, runner: runner, verbose: options.verbose)

        guard execution.result.succeeded else {
            throw BuildExecutor.failure(.buildFailed, "Build failed", from: execution)
        }

        return BuildPayload(
            scheme: config.scheme,
            configuration: config.configuration,
            resolution: choice.resolution,
            build: execution.result
        )
    }
}
