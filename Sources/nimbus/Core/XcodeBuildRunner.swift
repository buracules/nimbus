import Foundation

/// Builds xcodebuild argument lists and runs builds with formatted output.
struct XcodeBuildRunner {
    let config: NimbusConfig
    let verbose: Bool
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
    func buildArguments(for action: Action, destination: String? = nil) throws -> [String] {
        commonArguments(destination: destination) + [action.rawValue]
    }

    /// The destination this runner builds for: an explicit UDID when one was
    /// resolved, otherwise a name/OS destination derived from the config.
    var resolvedDestination: String? {
        if let udid = destinationUDID {
            return "platform=iOS Simulator,id=\(udid)"
        }
        return simulatorDestination(device: config.device, os: config.os)
    }

    /// Build a destination string for a simulator.
    func simulatorDestination(device: String?, os: String?) -> String? {
        guard device != nil || os != nil else { return nil }
        var parts = ["platform=iOS Simulator"]
        if let device = device {
            parts.append("name=\(device)")
        }
        if let os = os {
            parts.append("OS=\(os)")
        }
        return parts.joined(separator: ",")
    }

    /// Execute xcodebuild with the given action, streaming formatted output.
    @discardableResult
    func execute(action: Action) throws -> Bool {
        guard let xcodebuild = ProjectDetector.findXcodebuild() else {
            Console.error("xcodebuild not found. Is Xcode installed?")
            return false
        }

        let args = try buildArguments(for: action, destination: resolvedDestination)

        Console.verbose("xcodebuild \(args.joined(separator: " "))", isVerbose: verbose)

        let timer = BuildTimer()

        // Check if xcbeautify is available and desired
        let useXcbeautify = shouldUseXcbeautify()

        if useXcbeautify, let xcbeautifyPath = ProcessRunner.which("xcbeautify") {
            return try runWithXcbeautify(
                xcodebuild: xcodebuild,
                args: args,
                xcbeautifyPath: xcbeautifyPath,
                timer: timer
            )
        } else {
            return try runWithBuiltInFormatter(
                xcodebuild: xcodebuild,
                args: args,
                timer: timer
            )
        }
    }

    // MARK: - Built Product Discovery

    /// Ask xcodebuild where it puts the built .app for this configuration.
    ///
    /// Costs roughly 1-3 s, so only `run`/`logs` should call it — never plain
    /// `build`. Returns nil when xcodebuild is missing or reports no app target.
    func builtProductPath() -> String? {
        guard let xcodebuild = ProjectDetector.findXcodebuild() else { return nil }

        let args = commonArguments(destination: resolvedDestination) + ["-showBuildSettings", "-json"]
        Console.verbose("xcodebuild \(args.joined(separator: " "))", isVerbose: verbose)

        guard let result = try? ProcessRunner.run(xcodebuild, arguments: args), result.succeeded else {
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
    /// fallback. Returns nil when neither finds an app that exists on disk.
    func locateAppBundle() -> String? {
        if let path = builtProductPath() {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
            Console.verbose(
                "Build settings point at \(path), which does not exist — falling back to DerivedData search",
                isVerbose: verbose
            )
        } else {
            Console.verbose(
                "Could not read built product path from build settings — falling back to DerivedData search",
                isVerbose: verbose
            )
        }

        guard let scheme = config.scheme else { return nil }
        return SimulatorManager.findAppBundle(scheme: scheme, configuration: config.configuration ?? "Debug")
    }

    private func shouldUseXcbeautify() -> Bool {
        if let explicit = config.xcbeautify {
            return explicit
        }
        // Auto-detect: use if available
        return ProcessRunner.which("xcbeautify") != nil
    }

    private func runWithXcbeautify(
        xcodebuild: String,
        args: [String],
        xcbeautifyPath: String,
        timer: BuildTimer
    ) throws -> Bool {
        let xcodeBuildProcess = Process()
        xcodeBuildProcess.executableURL = URL(fileURLWithPath: xcodebuild)
        xcodeBuildProcess.arguments = args

        let xcbeautifyProcess = Process()
        xcbeautifyProcess.executableURL = URL(fileURLWithPath: xcbeautifyPath)

        let pipe = Pipe()
        xcodeBuildProcess.standardOutput = pipe
        xcodeBuildProcess.standardError = pipe
        xcbeautifyProcess.standardInput = pipe.fileHandleForReading

        xcbeautifyProcess.standardOutput = FileHandle.standardOutput
        xcbeautifyProcess.standardError = FileHandle.standardError

        try xcodeBuildProcess.run()
        try xcbeautifyProcess.run()

        // Close the parent's copy of the write end immediately.
        // Only xcodebuild needs it — once it exits, xcbeautify will see EOF.
        pipe.fileHandleForWriting.closeFile()

        xcodeBuildProcess.waitUntilExit()
        xcbeautifyProcess.waitUntilExit()

        let success = xcodeBuildProcess.terminationStatus == 0
        printTimeSummary(success: success, timer: timer)
        return success
    }

    private func runWithBuiltInFormatter(
        xcodebuild: String,
        args: [String],
        timer: BuildTimer
    ) throws -> Bool {
        let reporter = ProgressReporter(verbose: verbose)

        let exitCode = try ProcessRunner.stream(
            xcodebuild,
            arguments: args
        ) { line in
            if let formatted = reporter.format(line: line) {
                print(formatted)
            }
        }

        let success = exitCode == 0
        printTimeSummary(success: success, timer: timer)
        return success
    }

    private func printTimeSummary(success: Bool, timer: BuildTimer) {
        if success {
            Console.success("Built in \(timer.formatted)")
        } else {
            Console.error("Build failed after \(timer.formatted)")
        }
    }
}
