import ArgumentParser
import Foundation

struct TestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run unit tests"
    )

    @OptionGroup var options: SharedOptions

    mutating func run() throws {
        let config = try options.resolvedConfig()

        Console.step("Testing \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, verbose: options.verbose)
        let success = try runner.execute(action: .test)

        if !success {
            throw ExitCode.failure
        }
    }
}
