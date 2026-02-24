import ArgumentParser
import Foundation

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the project"
    )

    @OptionGroup var options: SharedOptions

    mutating func run() throws {
        let config = try options.resolvedConfig()

        Console.step("Building \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, verbose: options.verbose)
        let success = try runner.execute(action: .build)

        if !success {
            throw ExitCode.failure
        }
    }
}
