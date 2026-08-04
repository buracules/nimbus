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
        let choice = try DeviceSelection.choose(
            config: config,
            interactive: interactive,
            verbose: options.verbose
        )

        Console.step("Testing \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, destinationUDID: choice.device.udid)
        let result = try BuildExecutor.execute(action: .test, runner: runner, verbose: options.verbose)

        if !result.succeeded {
            throw ExitCode.failure
        }
    }
}
