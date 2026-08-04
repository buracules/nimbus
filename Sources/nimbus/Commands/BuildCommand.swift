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
        guard let match = try DeviceResolver.resolve(config: config, interactive: interactive, verbose: options.verbose) else {
            throw ExitCode.failure
        }

        Console.step("Building \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(
            config: config,
            verbose: options.verbose,
            destinationUDID: match.device.udid
        )
        let success = try runner.execute(action: .build)

        if !success {
            throw ExitCode.failure
        }
    }
}
