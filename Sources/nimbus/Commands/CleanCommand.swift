import ArgumentParser
import Foundation

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean build artifacts"
    )

    @OptionGroup var options: SharedOptions

    mutating func run() throws {
        let options = self.options

        try CommandRunner.run("clean", json: options.json) {
            try Self.perform(options: options)
        }
    }

    private static func perform(options: SharedOptions) throws -> CleanPayload {
        let config = try options.resolvedConfig()

        Console.step("Cleaning \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config)
        let execution = try BuildExecutor.execute(action: .clean, runner: runner, verbose: options.verbose)

        guard execution.result.succeeded else {
            throw BuildExecutor.failure(.cleanFailed, "Clean failed", from: execution)
        }

        Console.success("Clean complete")
        return CleanPayload(
            scheme: config.scheme,
            configuration: config.configuration,
            clean: execution.result
        )
    }
}
