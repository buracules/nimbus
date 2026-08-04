import XCTest
@testable import nimbus

/// Cancellation is the part that punishes optimism, so it gets real evidence
/// rather than a happy-path check.
///
/// The child here is a stand-in for `simctl io recordVideo`: it does its real
/// work when it is *interrupted*, so a caller that can only kill it gets
/// nothing useful. That is the contract `ProcessRunner.Handle` exists to
/// support.
final class ProcessHandleTests: XCTestCase {
    /// Prints on startup, finalizes on SIGINT, otherwise runs forever.
    private let finalizingChild = """
    trap 'echo finalized; exit 0' INT
    echo started
    while true; do sleep 0.05; done
    """

    private func startFinalizingChild(
        onLine: @escaping (String) -> Void
    ) throws -> ProcessRunner.Handle {
        try ProcessRunner.start("/bin/sh", arguments: ["-c", finalizingChild], onStdout: onLine)
    }

    /// Collects lines from the handle's callbacks, which fire on the stream queue.
    private final class LineSink: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []

        func append(_ line: String) {
            lock.lock()
            defer { lock.unlock() }
            lines.append(line)
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return lines
        }
    }

    private func waitForFirstLine(from sink: LineSink) {
        let deadline = Date().addingTimeInterval(5)
        while sink.all.isEmpty && Date() < deadline {
            usleep(10_000)
        }
        XCTAssertFalse(sink.all.isEmpty, "child never produced its first line")
    }

    // MARK: - Cancellation

    /// The GUI-shaped path: nobody signals nimbus, something just calls stop().
    func testInterruptStopsTheChildAndLetsItFinalize() throws {
        let sink = LineSink()
        let handle = try startFinalizingChild(onLine: sink.append)
        waitForFirstLine(from: sink)

        handle.interrupt()
        let exitCode = handle.wait()

        XCTAssertEqual(exitCode, 0, "child should have exited through its own handler")
        XCTAssertEqual(sink.all, ["started", "finalized"])
        XCTAssertFalse(handle.isRunning)
    }

    /// Interrupting from another thread while wait() blocks is the real shape:
    /// the CLI waits on the main thread and a signal source stops it.
    func testInterruptFromAnotherThreadUnblocksWait() throws {
        let sink = LineSink()
        let handle = try startFinalizingChild(onLine: sink.append)
        waitForFirstLine(from: sink)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            handle.interrupt()
        }

        let exitCode = handle.wait()
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(sink.all.last, "finalized")
    }

    /// Terminating skips the child's handler — the failure mode that makes a
    /// recording come out empty.
    func testTerminateSkipsTheChildsFinalizer() throws {
        let sink = LineSink()
        let handle = try startFinalizingChild(onLine: sink.append)
        waitForFirstLine(from: sink)

        handle.terminate()
        let exitCode = handle.wait()

        XCTAssertNotEqual(exitCode, 0, "terminate should not look like a clean stop")
        XCTAssertFalse(sink.all.contains("finalized"))
    }

    // MARK: - Handle invariants

    func testWaitIsRepeatableAndStable() throws {
        let handle = try ProcessRunner.start("/bin/sh", arguments: ["-c", "echo hi"], onStdout: { _ in })
        let first = handle.wait()
        let second = handle.wait()
        let third = handle.wait()
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, first)
        XCTAssertEqual(third, first)
    }

    func testInterruptAfterExitIsHarmless() throws {
        let handle = try ProcessRunner.start("/bin/sh", arguments: ["-c", "echo hi"], onStdout: { _ in })
        XCTAssertEqual(handle.wait(), 0)
        handle.interrupt()
        handle.terminate()
        XCTAssertEqual(handle.wait(), 0)
    }

    /// Output produced right up to the interrupt must still be delivered:
    /// cancelling must not lose the tail. Repeated, because a lost-output race
    /// shows up intermittently or not at all.
    func testCancellationStillDeliversEveryLine() throws {
        for iteration in 0..<25 {
            let sink = LineSink()
            let handle = try ProcessRunner.start(
                "/bin/sh",
                arguments: ["-c", "trap 'printf \"c\\nd\\n\"; exit 0' INT; printf 'a\\nb\\n'; while true; do sleep 0.05; done"],
                onStdout: sink.append
            )
            waitForFirstLine(from: sink)

            handle.interrupt()
            XCTAssertEqual(handle.wait(), 0, "iteration \(iteration)")
            XCTAssertEqual(sink.all, ["a", "b", "c", "d"], "iteration \(iteration)")
        }
    }

    /// `stream` is `start` plus `wait`, so it must keep the delivery guarantee
    /// the streaming tests already pin down.
    func testStreamStillDeliversUnterminatedTrailingOutput() throws {
        let sink = LineSink()
        let exitCode = try ProcessRunner.stream(
            "/bin/sh",
            arguments: ["-c", "printf 'a\\nb\\nc'"],
            onStdout: sink.append
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(sink.all, ["a", "b", "c"])
    }
}
