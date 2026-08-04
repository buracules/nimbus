import Foundation

/// Accumulates arbitrary chunks of bytes and emits whole newline-terminated
/// lines. Not thread-safe on its own — callers must serialize access.
struct LineBuffer {
    private static let newline = Data("\n".utf8)

    private var buffer = Data()

    /// Append a chunk and emit every complete line it produced.
    mutating func append(_ data: Data, emit: (String) -> Void) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newlineRange = buffer.range(of: Self.newline) {
            let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
            if let line = String(data: lineData, encoding: .utf8) {
                emit(line)
            }
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
        }
    }

    /// Emit whatever trailing bytes remain as a final, unterminated line.
    mutating func flush(emit: (String) -> Void) {
        guard !buffer.isEmpty else { return }
        if let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
            emit(line)
        }
        buffer.removeAll()
    }
}

/// Holds the two line buffers a streaming process writes into.
/// All access is serialized onto ProcessRunner's stream queue.
private final class StreamBuffers {
    var stdout = LineBuffer()
    var stderr = LineBuffer()
}

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

        // The readability handlers fire on their own queues. Every touch of the
        // line buffers — and therefore every line callback — is funnelled onto
        // this one serial queue, so there is exactly one writer at a time.
        let queue = DispatchQueue(label: "nimbus.process-stream")
        let buffers = StreamBuffers()
        let emitStderr = onStderr ?? onStdout

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            queue.async { buffers.stdout.append(data, emit: onStdout) }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            queue.async { buffers.stderr.append(data, emit: emitStderr) }
        }

        try process.run()
        process.waitUntilExit()

        // waitUntilExit does not guarantee the handlers drained the pipes, so
        // detach them and read whatever is left ourselves.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let trailingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let trailingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // sync on the serial queue is the barrier: everything the handlers
        // already enqueued has run before this block, and this block delivers
        // the tail before stream() returns.
        queue.sync {
            buffers.stdout.append(trailingStdout, emit: onStdout)
            buffers.stdout.flush(emit: onStdout)
            buffers.stderr.append(trailingStderr, emit: emitStderr)
            buffers.stderr.flush(emit: emitStderr)
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
