import Foundation

/// Auto-detects Xcode project files, workspaces, and schemes.
enum ProjectDetector {
    /// Find .xcworkspace files in the given directory (excluding SPM build artifacts).
    static func findWorkspaces(in directory: String = FileManager.default.currentDirectoryPath) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        return contents
            .filter { $0.hasSuffix(".xcworkspace") }
            .filter { !$0.contains(".build") && !$0.contains("project.xcworkspace") }
            .sorted()
    }

    /// Find .xcodeproj files in the given directory.
    static func findProjects(in directory: String = FileManager.default.currentDirectoryPath) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        return contents
            .filter { $0.hasSuffix(".xcodeproj") }
            .sorted()
    }

    /// Auto-detect the best project or workspace.
    /// Priority: .xcworkspace > .xcodeproj
    /// Returns (flag, value) e.g. ("-workspace", "Foo.xcworkspace").
    static func detectProjectFile(in directory: String = FileManager.default.currentDirectoryPath) -> (flag: String, value: String)? {
        let workspaces = findWorkspaces(in: directory)
        if let first = workspaces.first {
            return ("-workspace", first)
        }
        let projects = findProjects(in: directory)
        if let first = projects.first {
            return ("-project", first)
        }
        return nil
    }

    /// Use `xcodebuild -list -json` to get available schemes.
    static func detectSchemes(
        projectFlag: String? = nil,
        projectValue: String? = nil
    ) -> [String] {
        var args = ["-list", "-json"]
        if let flag = projectFlag, let value = projectValue {
            args.insert(contentsOf: [flag, value], at: 0)
        }

        guard let xcodebuild = findXcodebuild() else { return [] }
        guard let result = try? ProcessRunner.run(xcodebuild, arguments: args),
              result.succeeded else { return [] }

        return parseSchemes(from: result.stdout)
    }

    /// Parse schemes from `xcodebuild -list -json` output.
    static func parseSchemes(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Try workspace key first, then project key
        let container = (root["workspace"] as? [String: Any]) ?? (root["project"] as? [String: Any])
        guard let schemes = container?["schemes"] as? [String] else { return [] }
        return schemes
    }

    /// Find the xcodebuild executable.
    static func findXcodebuild() -> String? {
        // Common location
        let defaultPath = "/usr/bin/xcodebuild"
        if FileManager.default.fileExists(atPath: defaultPath) {
            return defaultPath
        }
        return ProcessRunner.which("xcodebuild")
    }
}
