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

    @Flag(name: .long, help: "Emit a JSON result envelope on stdout instead of human output")
    var json = false

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

            if !schemes.isEmpty {
                Console.verbose("Candidate schemes: \(schemes.joined(separator: ", "))", isVerbose: verbose)
            }

            if let selection = Self.selectSchemeWithReason(from: schemes, projectName: projectFile?.value) {
                merged.scheme = selection.scheme
                Console.verbose(
                    "Auto-detected scheme: \(selection.scheme) — \(selection.reason)",
                    isVerbose: verbose
                )
            }
        }

        return merged
    }

    // MARK: - Scheme Auto-detection

    /// Scheme name prefixes that almost always belong to a vendored dependency
    /// rather than the app being built.
    static let dependencySchemePrefixes = ["Facebook", "FBSDK", "Firebase", "Google", "Adjust"]

    struct SchemeSelection {
        let scheme: String
        let reason: String
    }

    /// Pick the scheme most likely to be the app, given the project file name.
    ///
    /// Order: exact project-name match, then project-name prefix match, then
    /// the first scheme that is neither a known dependency nor a test bundle.
    /// Test schemes are only ever chosen when nothing else is left.
    static func selectScheme(from schemes: [String], projectName: String?) -> String? {
        selectSchemeWithReason(from: schemes, projectName: projectName)?.scheme
    }

    static func selectSchemeWithReason(from schemes: [String], projectName: String?) -> SchemeSelection? {
        guard let first = schemes.first else { return nil }

        if let projectName {
            let baseName = (projectName as NSString).deletingPathExtension
            if let match = schemes.first(where: { $0 == baseName }) {
                return SchemeSelection(scheme: match, reason: "exactly matches project name '\(baseName)'")
            }
            // Prefer a non-test prefix match ("MyApp-Debug" over "MyAppTests").
            if let match = schemes.first(where: { $0.hasPrefix(baseName) && !isTestScheme($0) }) {
                return SchemeSelection(scheme: match, reason: "prefix-matches project name '\(baseName)'")
            }
            if let match = schemes.first(where: { $0.hasPrefix(baseName) }) {
                return SchemeSelection(
                    scheme: match,
                    reason: "prefix-matches project name '\(baseName)' (only test schemes matched)"
                )
            }
        }

        if let match = schemes.first(where: { !isDependencyScheme($0) && !isTestScheme($0) }) {
            return SchemeSelection(scheme: match, reason: "first scheme that is neither a dependency nor a test bundle")
        }
        if let match = schemes.first(where: { !isDependencyScheme($0) }) {
            return SchemeSelection(scheme: match, reason: "first non-dependency scheme (all were test bundles)")
        }
        return SchemeSelection(scheme: first, reason: "only candidate available")
    }

    static func isTestScheme(_ scheme: String) -> Bool {
        scheme.hasSuffix("Tests") || scheme.hasSuffix("UITests")
    }

    static func isDependencyScheme(_ scheme: String) -> Bool {
        dependencySchemePrefixes.contains { scheme.hasPrefix($0) }
    }
}
