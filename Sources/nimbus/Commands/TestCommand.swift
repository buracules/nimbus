import ArgumentParser
import Foundation

struct TestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run unit tests"
    )

    @OptionGroup var options: SharedOptions
    @Flag(name: .long, help: "Interactively select a simulator") var interactive = false

    mutating func run() throws {
        let config = try options.resolvedConfig()

        // Resolve a concrete simulator: without one, xcodebuild test runs with
        // no -destination and either fails or picks an arbitrary device.
        guard let match = try DeviceResolver.resolve(config: config, interactive: interactive, verbose: options.verbose) else {
            throw ExitCode.failure
        }

        Console.step("Testing \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(
            config: config,
            verbose: options.verbose,
            destinationUDID: match.device.udid
        )
        let success = try runner.execute(action: .test)

        if !success {
            throw ExitCode.failure
        }
    }
}
