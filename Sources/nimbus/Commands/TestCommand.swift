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
        let options = self.options
        let interactive = self.interactive

        try CommandRunner.run("test", json: options.json) {
            try Self.perform(options: options, interactive: interactive)
        }
    }

    private static func perform(options: SharedOptions, interactive: Bool) throws -> TestPayload {
        let selection = try options.resolvedSelection()
        let config = selection.config

        // Resolve a concrete simulator: without one, xcodebuild test runs with
        // no -destination and either fails or picks an arbitrary device.
        let choice = try DeviceSelection.choose(
            config: config,
            interactive: interactive,
            verbose: options.verbose,
            json: options.json,
            shadowedProjectDevice: selection.shadowedProjectDevice
        )

        Console.step("Testing \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, destinationUDID: choice.device.udid)
        let execution = try BuildExecutor.execute(action: .test, runner: runner, verbose: options.verbose)

        guard execution.result.succeeded else {
            throw BuildExecutor.failure(.testFailed, "Tests failed", from: execution)
        }

        return TestPayload(
            scheme: config.scheme,
            configuration: config.configuration,
            resolution: choice.resolution,
            test: execution.result
        )
    }
}
