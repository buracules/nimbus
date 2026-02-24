import Foundation
import Yams

enum ConfigLoader {
    static let fileName = "nimbus.yml"

    /// Path to the global configuration file.
    static var globalConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/nimbus/config.yml"
    }

    /// Search for nimbus.yml starting from the given directory, walking up to the root.
    static func findConfigFile(from directory: String = FileManager.default.currentDirectoryPath) -> String? {
        var dir = directory
        while true {
            let candidate = (dir as NSString).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    /// Load and parse the global config from ~/.config/nimbus/config.yml.
    static func loadGlobal() throws -> NimbusConfig {
        let path = globalConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return .empty
        }
        return try loadFile(at: path)
    }

    /// Load and parse the project nimbus.yml from the given directory (walking up).
    static func loadProject(from directory: String = FileManager.default.currentDirectoryPath) throws -> NimbusConfig {
        guard let path = findConfigFile(from: directory) else {
            return .empty
        }
        return try loadFile(at: path)
    }

    /// Load both global and project configs, merged (project wins over global).
    static func load(from directory: String = FileManager.default.currentDirectoryPath) throws -> NimbusConfig {
        let global = try loadGlobal()
        let project = try loadProject(from: directory)
        return global.merging(with: project)
    }

    /// Parse a specific YAML config file.
    static func loadFile(at path: String) throws -> NimbusConfig {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        let decoder = YAMLDecoder()
        return try decoder.decode(NimbusConfig.self, from: contents)
    }
}
