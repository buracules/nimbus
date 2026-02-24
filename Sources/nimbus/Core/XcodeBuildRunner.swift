import Foundation

/// Builds xcodebuild argument lists and runs builds with formatted output.
struct XcodeBuildRunner {
    let config: NimbusConfig
    let verbose: Bool

    enum Action: String {
        case build
        case test
        case clean
    }

    /// Build the xcodebuild arguments for the given action.
    func buildArguments(for action: Action, destination: String? = nil) throws -> [String] {
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

        // Action
        args.append(action.rawValue)

        return args
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

        let destination = simulatorDestination(device: config.device, os: config.os)
        let args = try buildArguments(for: action, destination: destination)

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
        xcbeautifyProcess.standardInput = pipe

        xcbeautifyProcess.standardOutput = FileHandle.standardOutput
        xcbeautifyProcess.standardError = FileHandle.standardError

        try xcodeBuildProcess.run()
        try xcbeautifyProcess.run()

        xcodeBuildProcess.waitUntilExit()
        // Close the write end so xcbeautify sees EOF
        pipe.fileHandleForWriting.closeFile()
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
