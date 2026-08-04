import XCTest
@testable import nimbus

final class LineBufferTests: XCTestCase {
    private func collect(_ body: (inout LineBuffer, (String) -> Void) -> Void) -> [String] {
        var buffer = LineBuffer()
        var lines: [String] = []
        body(&buffer) { lines.append($0) }
        return lines
    }

    func testEmitsCompleteLines() {
        let lines = collect { buffer, emit in
            buffer.append(Data("a\nb\nc\n".utf8), emit: emit)
        }
        XCTAssertEqual(lines, ["a", "b", "c"])
    }

    func testHoldsBackPartialLineUntilTerminated() {
        var buffer = LineBuffer()
        var lines: [String] = []
        let emit: (String) -> Void = { lines.append($0) }

        buffer.append(Data("hel".utf8), emit: emit)
        XCTAssertEqual(lines, [], "A partial line must not be emitted")

        buffer.append(Data("lo\n".utf8), emit: emit)
        XCTAssertEqual(lines, ["hello"])
    }

    func testChunkBoundariesMidLineAndMultiLine() {
        var buffer = LineBuffer()
        var lines: [String] = []
        let emit: (String) -> Void = { lines.append($0) }

        buffer.append(Data("one\ntw".utf8), emit: emit)
        buffer.append(Data("o\nthree\nfo".utf8), emit: emit)
        buffer.append(Data("ur\nfive".utf8), emit: emit)

        XCTAssertEqual(lines, ["one", "two", "three", "four"])

        buffer.flush(emit: emit)
        XCTAssertEqual(lines, ["one", "two", "three", "four", "five"])
    }

    func testNewlineArrivingInItsOwnChunk() {
        var buffer = LineBuffer()
        var lines: [String] = []
        let emit: (String) -> Void = { lines.append($0) }

        buffer.append(Data("alpha".utf8), emit: emit)
        buffer.append(Data("\n".utf8), emit: emit)

        XCTAssertEqual(lines, ["alpha"])
    }

    func testEmptyLinesArePreserved() {
        let lines = collect { buffer, emit in
            buffer.append(Data("a\n\nb\n".utf8), emit: emit)
        }
        XCTAssertEqual(lines, ["a", "", "b"])
    }

    func testEmptyChunkIsIgnored() {
        let lines = collect { buffer, emit in
            buffer.append(Data(), emit: emit)
        }
        XCTAssertEqual(lines, [])
    }

    func testFlushOnEmptyBufferEmitsNothing() {
        var buffer = LineBuffer()
        var lines: [String] = []
        buffer.append(Data("done\n".utf8), emit: { lines.append($0) })
        buffer.flush(emit: { lines.append($0) })
        XCTAssertEqual(lines, ["done"], "A trailing newline must not produce an extra empty line")
    }

    func testFlushIsIdempotent() {
        var buffer = LineBuffer()
        var lines: [String] = []
        let emit: (String) -> Void = { lines.append($0) }

        buffer.append(Data("tail".utf8), emit: emit)
        buffer.flush(emit: emit)
        buffer.flush(emit: emit)

        XCTAssertEqual(lines, ["tail"])
    }
}

final class ProcessRunnerStreamTests: XCTestCase {
    /// The unterminated final line must survive, and no line may be lost to the
    /// race between waitUntilExit and the readability handlers. Repeated,
    /// because a single pass will happily pass on a racy implementation.
    func testStreamDeliversEveryLineIncludingUnterminatedTail() throws {
        for iteration in 0..<50 {
            var lines: [String] = []
            let exitCode = try ProcessRunner.stream(
                "/bin/sh",
                arguments: ["-c", "printf 'a\\nb\\nc'"],
                onStdout: { lines.append($0) }
            )
            XCTAssertEqual(exitCode, 0, "iteration \(iteration)")
            XCTAssertEqual(lines, ["a", "b", "c"], "iteration \(iteration)")
        }
    }

    func testStreamSeparatesStdoutAndStderr() throws {
        for iteration in 0..<20 {
            var out: [String] = []
            var err: [String] = []
            let exitCode = try ProcessRunner.stream(
                "/bin/sh",
                arguments: ["-c", "printf 'out1\\nout2\\n'; printf 'err1\\nerr2' 1>&2"],
                onStdout: { out.append($0) },
                onStderr: { err.append($0) }
            )
            XCTAssertEqual(exitCode, 0, "iteration \(iteration)")
            XCTAssertEqual(out, ["out1", "out2"], "iteration \(iteration)")
            XCTAssertEqual(err, ["err1", "err2"], "iteration \(iteration)")
        }
    }

    func testStreamRoutesStderrToStdoutHandlerWhenNoStderrHandler() throws {
        var lines: [String] = []
        let exitCode = try ProcessRunner.stream(
            "/bin/sh",
            arguments: ["-c", "printf 'only-err\\n' 1>&2"],
            onStdout: { lines.append($0) }
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(lines, ["only-err"])
    }

    func testStreamDeliversLargeOutputAcrossManyReads() throws {
        let count = 5000
        var lines: [String] = []
        let exitCode = try ProcessRunner.stream(
            "/bin/sh",
            arguments: ["-c", "i=1; while [ $i -le \(count) ]; do echo line$i; i=$((i+1)); done"],
            onStdout: { lines.append($0) }
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(lines.count, count)
        XCTAssertEqual(lines.first, "line1")
        XCTAssertEqual(lines.last, "line\(count)")
    }

    func testStreamReportsNonZeroExitCode() throws {
        let exitCode = try ProcessRunner.stream(
            "/bin/sh",
            arguments: ["-c", "exit 3"],
            onStdout: { _ in }
        )
        XCTAssertEqual(exitCode, 3)
    }
}
