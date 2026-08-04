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

    /// A child process that is already running, which the caller can stop
    /// without stopping itself.
    ///
    /// `stream` blocks until the child exits, so for a long time the only stop
    /// signal nimbus had was Ctrl+C killing nimbus and taking the child with
    /// it. That does not work for an operation whose result depends on being
    /// asked to stop: `simctl io recordVideo` writes a usable movie when it is
    /// interrupted and a zero-byte file when it is terminated. It also does not
    /// work for any caller that is not a terminal — a GUI with a record button
    /// cannot stop a recording by quitting itself.
    ///
    /// So a long-running operation hands back one of these, and whoever owns
    /// the stop gesture maps onto it.
    ///
    /// `wait()` is expected to be called from one thread; `interrupt()` and
    /// `terminate()` are safe to call from another (a signal source, a UI
    /// callback) at any time, including after the child has already exited.
    final class Handle {
        private let process: Process
        private let stdoutPipe: Pipe
        private let stderrPipe: Pipe
        private let queue: DispatchQueue
        private let buffers: StreamBuffers
        private let onStdout: (String) -> Void
        private let onStderr: (String) -> Void

        private let stateLock = NSLock()
        private var hasFinished = false
        private var storedExitCode: Int32 = 0

        fileprivate init(
            process: Process,
            stdoutPipe: Pipe,
            stderrPipe: Pipe,
            queue: DispatchQueue,
            buffers: StreamBuffers,
            onStdout: @escaping (String) -> Void,
            onStderr: @escaping (String) -> Void
        ) {
            self.process = process
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.queue = queue
            self.buffers = buffers
            self.onStdout = onStdout
            self.onStderr = onStderr
        }

        var isRunning: Bool { process.isRunning }

        /// Ask the child to stop the way Ctrl+C would — the graceful stop, and
        /// the only one that makes `recordVideo` write its file.
        func interrupt() {
            guard process.isRunning else { return }
            process.interrupt()
        }

        /// Stop the child without asking. A child that finalizes work on
        /// interrupt will not get the chance.
        func terminate() {
            guard process.isRunning else { return }
            process.terminate()
        }

        /// Block until the child has exited and every line it wrote has been
        /// delivered. Returns the exit code. Safe to call more than once.
        @discardableResult
        func wait() -> Int32 {
            stateLock.lock()
            if hasFinished {
                defer { stateLock.unlock() }
                return storedExitCode
            }
            stateLock.unlock()

            process.waitUntilExit()

            stateLock.lock()
            defer { stateLock.unlock() }
            guard !hasFinished else { return storedExitCode }

            drain()
            storedExitCode = process.terminationStatus
            hasFinished = true
            return storedExitCode
        }

        /// waitUntilExit does not guarantee the readability handlers drained
        /// the pipes, so detach them and read whatever is left ourselves.
        private func drain() {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let trailingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let trailingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            // sync on the serial queue is the barrier: everything the handlers
            // already enqueued has run before this block, and this block
            // delivers the tail before wait() returns.
            queue.sync {
                buffers.stdout.append(trailingStdout, emit: onStdout)
                buffers.stdout.flush(emit: onStdout)
                buffers.stderr.append(trailingStderr, emit: onStderr)
                buffers.stderr.flush(emit: onStderr)
            }
        }
    }

    /// Start a command and return a handle to it. The caller decides when to
    /// stop it and when to wait for it.
    static func start(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        onStdout: @escaping (String) -> Void,
        onStderr: ((String) -> Void)? = nil
    ) throws -> Handle {
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

        return Handle(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            queue: queue,
            buffers: buffers,
            onStdout: onStdout,
            onStderr: emitStderr
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
        try start(
            executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            onStdout: onStdout,
            onStderr: onStderr
        ).wait()
    }

    /// Find an executable in PATH using `which`.
    static func which(_ command: String) -> String? {
        let result = try? run("/usr/bin/which", arguments: [command])
        guard let result, result.succeeded else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
