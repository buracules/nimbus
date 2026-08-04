import XCTest
@testable import nimbus

final class SchemeSelectionTests: XCTestCase {

    func testEmptyListReturnsNil() {
        XCTAssertNil(SharedOptions.selectScheme(from: [], projectName: "MyApp.xcodeproj"))
        XCTAssertNil(SharedOptions.selectScheme(from: [], projectName: nil))
    }

    func testSingleSchemeIsChosen() {
        XCTAssertEqual(
            SharedOptions.selectScheme(from: ["OnlyOne"], projectName: nil),
            "OnlyOne"
        )
    }

    func testExactProjectNameMatchWins() {
        let schemes = ["Alpha", "MyApp", "MyApp-Debug"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: "MyApp.xcodeproj"),
            "MyApp"
        )
    }

    func testExactMatchWorksForWorkspaces() {
        let schemes = ["Pods", "MyApp"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: "MyApp.xcworkspace"),
            "MyApp"
        )
    }

    func testPrefixMatchWhenNoExactMatch() {
        let schemes = ["Alpha", "MyApp-Debug"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: "MyApp.xcodeproj"),
            "MyApp-Debug"
        )
    }

    func testPrefixMatchSkipsTestSchemes() {
        // "MyAppTests" comes first and prefix-matches, but is a test bundle.
        let schemes = ["MyAppTests", "MyAppUITests", "MyApp-Debug"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: "MyApp.xcodeproj"),
            "MyApp-Debug"
        )
    }

    func testTestSchemeIsChosenOnlyWhenNothingElseMatches() {
        let schemes = ["MyAppTests"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: "MyApp.xcodeproj"),
            "MyAppTests"
        )
    }

    func testDependencySchemesAreSkipped() {
        let schemes = ["FirebaseCore", "GoogleUtilities", "FBSDKCoreKit", "MyApp"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: nil),
            "MyApp"
        )
    }

    func testTestSchemesAreSkippedWithoutAProjectName() {
        let schemes = ["MyAppTests", "MyAppUITests", "MyApp"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: nil),
            "MyApp"
        )
    }

    func testFallsBackToATestSchemeWhenEveryCandidateIsOne() {
        let schemes = ["AlphaTests", "BetaUITests"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: nil),
            "AlphaTests"
        )
    }

    func testFallsBackToADependencySchemeWhenEveryCandidateIsOne() {
        let schemes = ["FirebaseCore", "GoogleUtilities"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: nil),
            "FirebaseCore"
        )
    }

    func testProjectNameThatMatchesNothingFallsThroughToHeuristics() {
        let schemes = ["FirebaseCore", "SomethingElse"]
        XCTAssertEqual(
            SharedOptions.selectScheme(from: schemes, projectName: "Unrelated.xcodeproj"),
            "SomethingElse"
        )
    }

    // MARK: - Reasons

    func testSelectionReasonsAreReported() {
        XCTAssertEqual(
            SharedOptions.selectSchemeWithReason(from: ["MyApp"], projectName: "MyApp.xcodeproj")?.reason,
            "exactly matches project name 'MyApp'"
        )
        XCTAssertEqual(
            SharedOptions.selectSchemeWithReason(from: ["MyApp-Debug"], projectName: "MyApp.xcodeproj")?.reason,
            "prefix-matches project name 'MyApp'"
        )
        XCTAssertEqual(
            SharedOptions.selectSchemeWithReason(from: ["FirebaseCore", "MyApp"], projectName: nil)?.reason,
            "first scheme that is neither a dependency nor a test bundle"
        )
    }

    // MARK: - Classification helpers

    func testIsTestScheme() {
        XCTAssertTrue(SharedOptions.isTestScheme("MyAppTests"))
        XCTAssertTrue(SharedOptions.isTestScheme("MyAppUITests"))
        XCTAssertFalse(SharedOptions.isTestScheme("MyApp"))
        XCTAssertFalse(SharedOptions.isTestScheme("TestsRunner"))
    }

    func testIsDependencyScheme() {
        XCTAssertTrue(SharedOptions.isDependencyScheme("FirebaseAnalytics"))
        XCTAssertTrue(SharedOptions.isDependencyScheme("FBSDKCoreKit"))
        XCTAssertFalse(SharedOptions.isDependencyScheme("MyApp"))
    }
}
