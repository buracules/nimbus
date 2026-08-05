import XCTest
@testable import nimbus

/// Diagnostics are the only reason a `--json` caller gets for a failed build,
/// so what gets kept and what gets dropped is behaviour worth pinning.
final class BuildDiagnosticsTests: XCTestCase {
    private func collect(_ lines: [String]) -> [String] {
        var diagnostics = BuildDiagnostics()
        for line in lines { diagnostics.consider(line) }
        return diagnostics.lines
    }

    func testKeepsCompilerErrors() {
        let kept = collect([
            "CompileSwift normal arm64 /src/ContentView.swift",
            "/src/ContentView.swift:12:3: error: cannot convert value of type 'String' to 'Int'",
            "** BUILD FAILED **",
        ])
        XCTAssertEqual(kept, ["/src/ContentView.swift:12:3: error: cannot convert value of type 'String' to 'Int'"])
    }

    func testKeepsXcodebuildsOwnErrors() {
        let kept = collect(["xcodebuild: error: Scheme App is not currently configured for the test action."])
        XCTAssertEqual(kept.count, 1)
    }

    func testKeepsFailingTestCases() {
        let kept = collect([
            "Test Case '-[AppTests.MathTests testAdds]' started.",
            "Test Case '-[AppTests.MathTests testAdds]' passed (0.001 seconds).",
            "Test Case '-[AppTests.MathTests testSubtracts]' failed (0.002 seconds).",
        ])
        XCTAssertEqual(kept, ["Test Case '-[AppTests.MathTests testSubtracts]' failed (0.002 seconds)."])
    }

    func testDropsProgressAndWarnings() {
        let kept = collect([
            "CompileC /build/foo.o",
            "Ld /build/App.app/App normal",
            "/src/Old.swift:4:1: warning: 'thing' is deprecated",
            "** BUILD SUCCEEDED **",
        ])
        XCTAssertTrue(kept.isEmpty, "warnings and progress are not the reason a build failed")
    }

    func testTrimsAndDeduplicates() {
        // xcodebuild repeats the same diagnostic once per target that saw it.
        let kept = collect([
            "  /src/A.swift:1:1: error: boom",
            "/src/A.swift:1:1: error: boom",
            "\t/src/A.swift:1:1: error: boom",
        ])
        XCTAssertEqual(kept, ["/src/A.swift:1:1: error: boom"])
    }

    func testStopsAtTheLimitSoAnEnvelopeNeverBecomesALogFile() {
        let kept = collect((0..<500).map { "/src/File\($0).swift:1:1: error: boom \($0)" })
        XCTAssertEqual(kept.count, BuildDiagnostics.limit)
        XCTAssertEqual(kept.first, "/src/File0.swift:1:1: error: boom 0", "the first errors are the cause")
    }
}
