import Foundation

/// Represents the contents of a nimbus.yml configuration file.
struct NimbusConfig: Codable, Equatable {
    var project: String?
    var workspace: String?
    var scheme: String?
    var device: String?
    var os: String?
    var configuration: String?
    var xcbeautify: Bool?

    /// Merge another config on top of this one. Non-nil values in `other` take precedence.
    func merging(with other: NimbusConfig) -> NimbusConfig {
        NimbusConfig(
            project: other.project ?? project,
            workspace: other.workspace ?? workspace,
            scheme: other.scheme ?? scheme,
            device: other.device ?? device,
            os: other.os ?? os,
            configuration: other.configuration ?? configuration,
            xcbeautify: other.xcbeautify ?? xcbeautify
        )
    }

    static let empty = NimbusConfig()

    /// Generate YAML string representation for writing to nimbus.yml.
    func toYAML() -> String {
        var lines: [String] = []
        if let workspace = workspace {
            lines.append("workspace: \(workspace)")
        } else if let project = project {
            lines.append("project: \(project)")
        }
        if let scheme = scheme {
            lines.append("scheme: \(scheme)")
        }
        if let device = device {
            lines.append("device: \"\(device)\"")
        }
        if let os = os {
            lines.append("os: \"\(os)\"")
        }
        if let configuration = configuration {
            lines.append("configuration: \(configuration)")
        }
        if let xcbeautify = xcbeautify {
            lines.append("xcbeautify: \(xcbeautify)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
