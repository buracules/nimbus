import ArgumentParser
import Foundation

/// CLI flags shared across build/run/test/clean commands.
/// These override values from nimbus.yml.
struct SharedOptions: ParsableArguments {
    @Option(name: .long, help: "Xcode scheme to use")
    var scheme: String?

    @Option(name: .long, help: "Build configuration (Debug/Release)")
    var configuration: String?

    @Option(name: .long, help: "Simulator device name")
    var device: String?

    @Option(name: .long, help: "Simulator OS version")
    var os: String?

    @Flag(name: .long, help: "Show verbose output")
    var verbose = false

    /// Load configs and merge: global < project < CLI flags.
    func resolvedConfig() throws -> NimbusConfig {
        let globalConfig = try ConfigLoader.loadGlobal()
        let projectConfig = try ConfigLoader.loadProject()
        let cliConfig = NimbusConfig(
            project: nil,
            workspace: nil,
            scheme: scheme,
            device: device,
            os: os,
            configuration: configuration,
            xcbeautify: nil
        )

        if globalConfig != .empty {
            Console.verbose("Loaded global config: \(ConfigLoader.globalConfigPath)", isVerbose: verbose)
        }
        if let projectPath = ConfigLoader.findConfigFile() {
            Console.verbose("Loaded project config: \(projectPath)", isVerbose: verbose)
        }

        var merged = globalConfig.merging(with: projectConfig).merging(with: cliConfig)

        // If still no scheme, try auto-detection
        if merged.scheme == nil {
            let projectFile = ProjectDetector.detectProjectFile()
            let schemes = ProjectDetector.detectSchemes(
                projectFlag: projectFile?.flag,
                projectValue: projectFile?.value
            )
            if let first = schemes.first {
                merged.scheme = first
                Console.verbose("Auto-detected scheme: \(first)", isVerbose: verbose)
            }
        }

        return merged
    }
}
