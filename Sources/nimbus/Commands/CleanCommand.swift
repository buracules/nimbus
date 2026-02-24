import ArgumentParser
import Foundation

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean build artifacts"
    )

    @OptionGroup var options: SharedOptions

    mutating func run() throws {
        let config = try options.resolvedConfig()

        Console.step("Cleaning \(config.scheme ?? "project")...")

        let runner = XcodeBuildRunner(config: config, verbose: options.verbose)
        let success = try runner.execute(action: .clean)

        if success {
            Console.success("Clean complete")
        } else {
            throw ExitCode.failure
        }
    }
}
