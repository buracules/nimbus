import Foundation

/// Wrapper around Foundation.Process for running shell commands.
enum ProcessRunner {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var succeeded: Bool { exitCode == 0 }
    }

    /// Run a command and capture all output.
    @discardableResult
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }
        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return Output(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// Run a command and stream output line-by-line through a handler.
    /// Returns the exit code.
    @discardableResult
    static func stream(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        onStdout: @escaping (String) -> Void,
        onStderr: ((String) -> Void)? = nil
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }
        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutBuffer = Data()
        var stderrBuffer = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stdoutBuffer.append(data)
            while let newlineRange = stdoutBuffer.range(of: Data("\n".utf8)) {
                let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newlineRange.lowerBound]
                if let line = String(data: lineData, encoding: .utf8) {
                    onStdout(line)
                }
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newlineRange.lowerBound)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
            while let newlineRange = stderrBuffer.range(of: Data("\n".utf8)) {
                let lineData = stderrBuffer[stderrBuffer.startIndex..<newlineRange.lowerBound]
                if let line = String(data: lineData, encoding: .utf8) {
                    (onStderr ?? onStdout)(line)
                }
                stderrBuffer.removeSubrange(stderrBuffer.startIndex...newlineRange.lowerBound)
            }
        }

        try process.run()
        process.waitUntilExit()

        // Flush remaining buffers
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if let remaining = String(data: stdoutBuffer, encoding: .utf8), !remaining.isEmpty {
            onStdout(remaining)
        }
        if let remaining = String(data: stderrBuffer, encoding: .utf8), !remaining.isEmpty {
            (onStderr ?? onStdout)(remaining)
        }

        return process.terminationStatus
    }

    /// Find an executable in PATH using `which`.
    static func which(_ command: String) -> String? {
        let result = try? run("/usr/bin/which", arguments: [command])
        guard let result, result.succeeded else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
