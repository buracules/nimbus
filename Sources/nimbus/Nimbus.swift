import ArgumentParser

@main
struct Nimbus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nimbus",
        abstract: "A simple, fast iOS build tool",
        version: "0.1.0",
        subcommands: [
            BuildCommand.self,
            RunCommand.self,
            TestCommand.self,
            CleanCommand.self,
            DevicesCommand.self,
            UseCommand.self,
            ProjectsCommand.self,
            LogsCommand.self,
            SimCommand.self,
            InitCommand.self,
        ],
        defaultSubcommand: BuildCommand.self
    )
}
