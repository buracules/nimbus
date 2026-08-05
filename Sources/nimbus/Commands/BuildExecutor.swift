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
    /// An xcodebuild action that has finished, plus the lines that explain it
    /// if it failed.
    ///
    /// `BuildResult` is core's and says whether the action succeeded.
    /// Diagnostics are the CLI's problem: they exist so `--json` can answer
    /// *why* a build failed without a caller scraping the terminal.
    struct Execution {
        let result: BuildResult
        let diagnostics: [String]
    }

    static func execute(
        action: XcodeBuildRunner.Action,
        runner: XcodeBuildRunner,
        verbose: Bool
    ) throws -> Execution {
        guard let xcodebuild = ProjectDetector.findXcodebuild() else {
            throw NimbusFailure(.xcodebuildNotFound, "xcodebuild not found. Is Xcode installed?")
        }

        let args = runner.buildArguments(for: action, destination: runner.resolvedDestination)
        Console.verbose("xcodebuild \(args.joined(separator: " "))", isVerbose: verbose)

        let execution: Execution
        if Console.isMachineReadable {
            // xcbeautify writes straight to this process's stdout, which is
            // reserved for the envelope, so it is not an option here. The
            // formatter is also pointless — nothing decorated is going to be
            // read. Collect the reason instead, and only echo the raw log to
            // stderr when someone asked to watch it.
            execution = try runCollectingDiagnostics(runner: runner, action: action, verbose: verbose)
        } else if shouldUseXcbeautify(config: runner.config), let xcbeautify = ProcessRunner.which("xcbeautify") {
            let result = try runPipedThroughXcbeautify(
                xcodebuild: xcodebuild,
                args: args,
                xcbeautifyPath: xcbeautify
            )
            execution = Execution(result: result, diagnostics: [])
        } else {
            let reporter = ProgressReporter(verbose: verbose)
            var diagnostics = BuildDiagnostics()
            let result = try runner.run(action: action) { line in
                diagnostics.consider(line)
                if let formatted = reporter.format(line: line) {
                    print(formatted)
                }
            }
            execution = Execution(result: result, diagnostics: diagnostics.lines)
        }

        printTimeSummary(execution.result)
        return execution
    }

    private static func runCollectingDiagnostics(
        runner: XcodeBuildRunner,
        action: XcodeBuildRunner.Action,
        verbose: Bool
    ) throws -> Execution {
        var diagnostics = BuildDiagnostics()
        let result = try runner.run(action: action) { line in
            diagnostics.consider(line)
            Console.verbose(line, isVerbose: verbose)
        }
        return Execution(result: result, diagnostics: diagnostics.lines)
    }

    /// Turn a failed action into a coded failure carrying its reason.
    ///
    /// The elapsed time goes in the message because a failed action has no
    /// `data` in the envelope to put it in, and it is the one fact a human
    /// wants alongside "it failed".
    static func failure(_ code: NimbusErrorCode, _ message: String, from execution: Execution) -> NimbusFailure {
        NimbusFailure(
            code,
            "\(message) after \(BuildTimer.format(execution.result.duration))",
            exitCode: execution.result.exitCode,
            diagnostics: execution.diagnostics
        )
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

    /// Only successes are announced here. A failure is announced once, by
    /// whoever reports the failure — saying it in both places is how the human
    /// output ended up with two "Build failed" lines.
    private static func printTimeSummary(_ result: BuildResult) {
        guard result.succeeded else { return }
        Console.success("Built in \(BuildTimer.format(result.duration))")
    }
}
