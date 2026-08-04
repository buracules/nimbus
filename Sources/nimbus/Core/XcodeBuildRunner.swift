import Foundation

/// What an xcodebuild action did. The caller decides how to say it.
struct BuildResult {
    let succeeded: Bool
    let exitCode: Int32
    let duration: TimeInterval
}

/// Where the built `.app` is, and how that was worked out.
///
/// The diagnostic fields exist so a caller can explain the route it took
/// without this type printing anything.
struct AppBundleLocation {
    /// The app bundle to use, or nil when neither route found one on disk.
    let path: String?
    /// What `-showBuildSettings` reported; nil when it could not be read.
    let buildSettingsPath: String?
    /// Whether the build-settings path actually exists on disk.
    let buildSettingsPathExists: Bool

    /// True when `path` came from the DerivedData search rather than from
    /// build settings.
    var usedDerivedDataSearch: Bool {
        path != nil && !buildSettingsPathExists
    }
}

/// Builds xcodebuild argument lists and runs builds.
///
/// This owns the arguments and the outcome. It does not own the terminal: a
/// caller that wants formatted output takes the lines through `onOutputLine`,
/// and a caller that wants to pipe xcodebuild into something else takes
/// `buildArguments(for:destination:)` and spawns it itself. One source of
/// truth for the arguments, two transports.
struct XcodeBuildRunner {
    let config: NimbusConfig
    var destinationUDID: String? = nil

    enum Action: String {
        case build
        case test
        case clean
    }

    /// The project/scheme/configuration/destination arguments every xcodebuild
    /// invocation for this config shares.
    func commonArguments(destination: String? = nil) -> [String] {
        var args: [String] = []

        // Project or workspace
        if let workspace = config.workspace {
            args += ["-workspace", workspace]
        } else if let project = config.project {
            args += ["-project", project]
        } else if let detected = ProjectDetector.detectProjectFile() {
            args += [detected.flag, detected.value]
        }

        // Scheme
        if let scheme = config.scheme {
            args += ["-scheme", scheme]
        }

        // Configuration
        if let configuration = config.configuration {
            args += ["-configuration", configuration]
        }

        // Destination (for simulator builds)
        if let dest = destination {
            args += ["-destination", dest]
        }

        return args
    }

    /// Build the xcodebuild arguments for the given action.
    func buildArguments(for action: Action, destination: String? = nil) -> [String] {
        commonArguments(destination: destination) + [action.rawValue]
    }

    /// The arguments used to ask xcodebuild where it puts its products.
    var buildSettingsArguments: [String] {
        commonArguments(destination: resolvedDestination) + ["-showBuildSettings", "-json"]
    }

    /// The destination this runner builds for: the simulator that was actually
    /// resolved, or none.
    ///
    /// A configured device *name* is deliberately not a destination. Whether
    /// that name exists on this machine is the question device resolution
    /// answers, and passing it to xcodebuild unchecked is what made `build`
    /// and `clean` fail — for a minute at a time — against a config naming a
    /// simulator that was never installed. Actions that need a simulator get a
    /// resolved UDID; `clean` does not need one and gets nothing.
    var resolvedDestination: String? {
        destinationUDID.map { "platform=iOS Simulator,id=\($0)" }
    }

    /// Run xcodebuild for the given action, delivering each output line as it
    /// arrives.
    func run(action: Action, onOutputLine: @escaping (String) -> Void) throws -> BuildResult {
        guard let xcodebuild = ProjectDetector.findXcodebuild() else {
            throw NimbusError.notFound("xcodebuild")
        }

        let args = buildArguments(for: action, destination: resolvedDestination)
        let started = Date()
        let exitCode = try ProcessRunner.stream(xcodebuild, arguments: args, onStdout: onOutputLine)

        return BuildResult(
            succeeded: exitCode == 0,
            exitCode: exitCode,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Built Product Discovery

    /// Ask xcodebuild where it puts the built .app for this configuration.
    ///
    /// Costs roughly 1-3 s, so only `run`/`logs` should call it — never plain
    /// `build`. Returns nil when xcodebuild is missing or reports no app target.
    func builtProductPath() -> String? {
        guard let xcodebuild = ProjectDetector.findXcodebuild() else { return nil }

        guard let result = try? ProcessRunner.run(xcodebuild, arguments: buildSettingsArguments),
              result.succeeded else {
            return nil
        }
        return Self.parseBuiltProductPath(fromJSON: result.stdout)
    }

    /// Extract the built .app path from `xcodebuild -showBuildSettings -json`.
    /// The payload is an array of `{"target": ..., "buildSettings": {...}}`.
    static func parseBuiltProductPath(fromJSON json: String) -> String? {
        // xcodebuild sometimes prefixes the payload with notes/warnings.
        guard let arrayStart = json.firstIndex(of: "["),
              let data = String(json[arrayStart...]).data(using: .utf8),
              let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        for target in targets {
            guard let settings = target["buildSettings"] as? [String: Any],
                  let wrapperName = settings["WRAPPER_NAME"] as? String,
                  wrapperName.hasSuffix(".app") else {
                continue
            }
            if let buildDir = settings["TARGET_BUILD_DIR"] as? String, !buildDir.isEmpty {
                return "\(buildDir)/\(wrapperName)"
            }
            if let folder = settings["CODESIGNING_FOLDER_PATH"] as? String, !folder.isEmpty {
                return folder
            }
        }
        return nil
    }

    /// Locate the built .app: exact build settings first, DerivedData glob as a
    /// fallback. The returned value records which route produced the answer so
    /// the caller can explain it.
    func locateAppBundle() -> AppBundleLocation {
        let settingsPath = builtProductPath()

        if let settingsPath, FileManager.default.fileExists(atPath: settingsPath) {
            return AppBundleLocation(
                path: settingsPath,
                buildSettingsPath: settingsPath,
                buildSettingsPathExists: true
            )
        }

        var fallback: String? = nil
        if let scheme = config.scheme {
            fallback = SimulatorManager.findAppBundle(
                scheme: scheme,
                configuration: config.configuration ?? "Debug"
            )
        }

        return AppBundleLocation(
            path: fallback,
            buildSettingsPath: settingsPath,
            buildSettingsPathExists: false
        )
    }
}
