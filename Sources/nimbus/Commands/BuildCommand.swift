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
        let config = try options.resolvedConfig()

        // Resolve a concrete simulator like run/test do. Without this the
        // destination is `name=<configured device>` verbatim, which fails
        // whenever the configured name does not exist on this machine.
        let choice = try DeviceSelection.choose(
            config: config,
            interactive: interactive,
            verbose: options.verbose
        )

        Console.step("Building \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, destinationUDID: choice.device.udid)
        let result = try BuildExecutor.execute(action: .build, runner: runner, verbose: options.verbose)

        if !result.succeeded {
            throw ExitCode.failure
        }
    }
}
