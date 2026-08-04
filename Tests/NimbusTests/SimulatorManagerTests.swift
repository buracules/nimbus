import XCTest
@testable import nimbus

final class SimulatorManagerTests: XCTestCase {

    // MARK: - runtimeVersion(from:)

    func testRuntimeVersionFromIOSIdentifier() {
        XCTAssertEqual(
            SimulatorManager.runtimeVersion(from: "com.apple.CoreSimulator.SimRuntime.iOS-26-2"),
            "26.2"
        )
    }

    func testRuntimeVersionFromMajorOnlyIdentifier() {
        XCTAssertEqual(
            SimulatorManager.runtimeVersion(from: "com.apple.CoreSimulator.SimRuntime.iOS-26"),
            "26"
        )
    }

    func testRuntimeVersionFromTVOSAndWatchOSIdentifiers() {
        XCTAssertEqual(
            SimulatorManager.runtimeVersion(from: "com.apple.CoreSimulator.SimRuntime.tvOS-18-0"),
            "18.0"
        )
        XCTAssertEqual(
            SimulatorManager.runtimeVersion(from: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2"),
            "11.2"
        )
    }

    func testRuntimeVersionFromMalformedIdentifiers() {
        XCTAssertNil(SimulatorManager.runtimeVersion(from: ""))
        XCTAssertNil(SimulatorManager.runtimeVersion(from: "garbage"))
        XCTAssertNil(SimulatorManager.runtimeVersion(from: "com.apple.CoreSimulator.SimRuntime.iOS"))
        XCTAssertNil(SimulatorManager.runtimeVersion(from: "com.apple.CoreSimulator.SimRuntime."))
    }

    // MARK: - runtimePlatform(from:) / runtimeDisplayName(_:)

    func testRuntimePlatform() {
        XCTAssertEqual(
            SimulatorManager.runtimePlatform(from: "com.apple.CoreSimulator.SimRuntime.iOS-26-2"),
            "iOS"
        )
        XCTAssertEqual(
            SimulatorManager.runtimePlatform(from: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2"),
            "watchOS"
        )
    }

    func testRuntimeDisplayName() {
        XCTAssertEqual(
            SimulatorManager.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.iOS-18-0"),
            "iOS 18.0"
        )
        XCTAssertEqual(
            SimulatorManager.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.iOS-26-2"),
            "iOS 26.2"
        )
        XCTAssertEqual(
            SimulatorManager.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.watchOS-11-2"),
            "watchOS 11.2"
        )
    }

    func testRuntimeDisplayNameFallsBackForMalformedIdentifier() {
        XCTAssertEqual(SimulatorManager.runtimeDisplayName("garbage"), "garbage")
        XCTAssertEqual(
            SimulatorManager.runtimeDisplayName("com.apple.CoreSimulator.SimRuntime.iOS"),
            "iOS"
        )
    }

    // MARK: - runtimeMatches(_:os:)

    func testRuntimeMatchesExactVersion() {
        XCTAssertTrue(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "26.2")
        )
    }

    func testRuntimeMatchesMajorOnlyPrefix() {
        XCTAssertTrue(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "26")
        )
    }

    func testRuntimeDoesNotMatchSubstringFalsePositive() {
        // The bug this replaced: "6.2" substring-matched "...iOS-26-2".
        XCTAssertFalse(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "6.2")
        )
        XCTAssertFalse(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "6")
        )
    }

    func testRuntimeDoesNotMatchMoreSpecificRequestThanRuntime() {
        XCTAssertFalse(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26", os: "26.2")
        )
    }

    func testRuntimeMatchesDifferentMinorIsFalse() {
        XCTAssertFalse(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "26.1")
        )
    }

    func testRuntimeMatchesToleratesSurroundingWhitespace() {
        XCTAssertTrue(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: " 26.2 ")
        )
    }

    func testRuntimeMatchesOnNonIOSPlatforms() {
        XCTAssertTrue(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.watchOS-11-2", os: "11.2")
        )
        XCTAssertFalse(
            SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.tvOS-18-0", os: "8.0")
        )
    }

    func testRuntimeMatchesMalformedInputsReturnFalseWithoutCrashing() {
        XCTAssertFalse(SimulatorManager.runtimeMatches("garbage", os: "26.2"))
        XCTAssertFalse(SimulatorManager.runtimeMatches("", os: "26.2"))
        XCTAssertFalse(SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: ""))
        XCTAssertFalse(SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "..."))
        XCTAssertFalse(SimulatorManager.runtimeMatches("com.apple.CoreSimulator.SimRuntime.iOS-26-2", os: "abc"))
    }
}
