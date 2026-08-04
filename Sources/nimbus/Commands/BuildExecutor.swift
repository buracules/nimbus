import ArgumentParser
import Foundation

/// CLI-side execution of an xcodebuild action.
///
/// Core owns the arguments and the outcome; this owns everything the user
/// reads — which formatter runs, what gets printed, and the timing line at the
/// end. It also owns the second transport: piping xcodebuild into xcbeautify
/// means spawning xcodebuild here rather than through core, so the arguments
/// come from `XcodeBuildRunner.buildArguments` either way.
enum BuildExecutor {
    static func execute(
        action: XcodeBuildRunner.Action,
        runner: XcodeBuildRunner,
        verbose: Bool
    ) throws -> BuildResult {
        guard let xcodebuild = ProjectDetector.findXcodebuild() else {
            Console.error("xcodebuild not found. Is Xcode installed?")
            throw ExitCode.failure
        }

        let args = runner.buildArguments(for: action, destination: runner.resolvedDestination)
        Console.verbose("xcodebuild \(args.joined(separator: " "))", isVerbose: verbose)

        let result: BuildResult
        if shouldUseXcbeautify(config: runner.config), let xcbeautify = ProcessRunner.which("xcbeautify") {
            result = try runPipedThroughXcbeautify(
                xcodebuild: xcodebuild,
                args: args,
                xcbeautifyPath: xcbeautify
            )
        } else {
            let reporter = ProgressReporter(verbose: verbose)
            result = try runner.run(action: action) { line in
                if let formatted = reporter.format(line: line) {
                    print(formatted)
                }
            }
        }

        printTimeSummary(result)
        return result
    }

    // MARK: - App bundle

    /// Locate the built app and explain in verbose mode which route found it.
    /// Returns nil when neither route found an app on disk — the caller words
    /// that failure, since `run` and `logs` say different things about it.
    static func locateAppBundle(runner: XcodeBuildRunner, verbose: Bool) -> String? {
        Console.verbose(
            "xcodebuild \(runner.buildSettingsArguments.joined(separator: " "))",
            isVerbose: verbose
        )

        let location = runner.locateAppBundle()

        if location.buildSettingsPathExists == false {
            if let reported = location.buildSettingsPath {
                Console.verbose(
                    "Build settings point at \(reported), which does not exist — falling back to DerivedData search",
                    isVerbose: verbose
                )
            } else {
                Console.verbose(
                    "Could not read built product path from build settings — falling back to DerivedData search",
                    isVerbose: verbose
                )
            }
        }

        return location.path
    }

    // MARK: - Output transport

    private static func shouldUseXcbeautify(config: NimbusConfig) -> Bool {
        if let explicit = config.xcbeautify {
            return explicit
        }
        // Auto-detect: use if available
        return ProcessRunner.which("xcbeautify") != nil
    }

    private static func runPipedThroughXcbeautify(
        xcodebuild: String,
        args: [String],
        xcbeautifyPath: String
    ) throws -> BuildResult {
        let started = Date()

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

        let exitCode = xcodeBuildProcess.terminationStatus
        return BuildResult(
            succeeded: exitCode == 0,
            exitCode: exitCode,
            duration: Date().timeIntervalSince(started)
        )
    }

    private static func printTimeSummary(_ result: BuildResult) {
        let elapsed = BuildTimer.format(result.duration)
        if result.succeeded {
            Console.success("Built in \(elapsed)")
        } else {
            Console.error("Build failed after \(elapsed)")
        }
    }
}
