import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Generate nimbus.yml from auto-detected settings"
    )

    @Flag(name: .long, help: "Overwrite existing nimbus.yml")
    var force = false

    @Flag(name: .long, help: "Write to global config (~/.config/nimbus/config.yml) instead of project")
    var global = false

    mutating func run() throws {
        if global {
            try runGlobal()
        } else {
            try runProject()
        }
    }

    private func runGlobal() throws {
        let configPath = ConfigLoader.globalConfigPath
        let configDir = (configPath as NSString).deletingLastPathComponent

        if FileManager.default.fileExists(atPath: configPath) && !force {
            Console.error("\(configPath) already exists. Use --force to overwrite.")
            throw ExitCode.failure
        }

        // Create ~/.config/nimbus/ if it doesn't exist
        if !FileManager.default.fileExists(atPath: configDir) {
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }

        // Global config should only contain user preferences, not project-specific paths
        var config = NimbusConfig.empty
        config.configuration = "Debug"
        // Note: project, workspace, and scheme are intentionally omitted
        // They should be auto-detected per directory (works correctly in worktrees)

        let yaml = config.toYAML()
        try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)

        Console.success("Generated global config: \(configPath)")
        Console.info("Note: project/workspace/scheme are auto-detected per directory")
        print()
        print(yaml)
    }

    private func runProject() throws {
        let configPath = FileManager.default.currentDirectoryPath + "/nimbus.yml"

        if FileManager.default.fileExists(atPath: configPath) && !force {
            Console.error("nimbus.yml already exists. Use --force to overwrite.")
            throw ExitCode.failure
        }

        Console.step("Detecting project settings...")

        var config = NimbusConfig.empty

        // Detect project/workspace
        if let detected = ProjectDetector.detectProjectFile() {
            if detected.flag == "-workspace" {
                config.workspace = detected.value
            } else {
                config.project = detected.value
            }
            Console.info("Found: \(detected.value)")
        } else {
            Console.warning("No .xcodeproj or .xcworkspace found in current directory.")
        }

        // Detect schemes
        let projectFile = ProjectDetector.detectProjectFile()
        let schemes = ProjectDetector.detectSchemes(
            projectFlag: projectFile?.flag,
            projectValue: projectFile?.value
        )

        if let first = schemes.first {
            config.scheme = first
            Console.info("Scheme: \(first)")
            if schemes.count > 1 {
                Console.info("Other schemes: \(schemes.dropFirst().joined(separator: ", "))")
            }
        }

        // Set defaults
        config.configuration = "Debug"

        // Write config
        let yaml = config.toYAML()
        try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)

        Console.success("Generated nimbus.yml")
        print()
        print(yaml)
    }
}
