import XCTest

@testable import nimbus

/// The colour decision is a pure function precisely so these cases can be
/// checked without a terminal, a pipe, or a mutated environment.
final class ConsoleColorTests: XCTestCase {
    func testColorsWhenAttachedToATerminal() {
        XCTAssertTrue(
            Console.shouldColor(noColor: false, machineReadable: false, isTerminal: true)
        )
    }

    func testNoColorsWhenTheStreamIsNotATerminal() {
        XCTAssertFalse(
            Console.shouldColor(noColor: false, machineReadable: false, isTerminal: false)
        )
    }

    func testNoColorEnvironmentWinsOverATerminal() {
        XCTAssertFalse(
            Console.shouldColor(noColor: true, machineReadable: false, isTerminal: true)
        )
    }

    func testMachineReadableOutputIsNeverColored() {
        XCTAssertFalse(
            Console.shouldColor(noColor: false, machineReadable: true, isTerminal: true)
        )
    }

    func testColoredIsAnIdentityWhenColorIsOff() {
        // stdout is not a terminal under `swift test`, so the real emit path
        // must leave the text untouched — no stray escape sequences.
        XCTAssertEqual(Console.colored("plain", .red), "plain")
    }
}
