import XCTest
@testable import nimbus

final class LogsCommandPredicateTests: XCTestCase {

    func testPredicateMatchesProcessAndSubsystem() {
        XCTAssertEqual(
            LogsCommand.buildPredicate(executableName: "MyApp", bundleID: "com.example.MyApp"),
            "processImagePath ENDSWITH \"/MyApp\" OR subsystem == \"com.example.MyApp\""
        )
    }

    func testPredicateFallsBackToSubsystemOnlyWithoutExecutableName() {
        XCTAssertEqual(
            LogsCommand.buildPredicate(executableName: nil, bundleID: "com.example.MyApp"),
            "subsystem == \"com.example.MyApp\""
        )
        XCTAssertEqual(
            LogsCommand.buildPredicate(executableName: "", bundleID: "com.example.MyApp"),
            "subsystem == \"com.example.MyApp\""
        )
    }

    func testPredicateEscapesEmbeddedQuotesAndBackslashes() {
        XCTAssertEqual(
            LogsCommand.buildPredicate(executableName: "My\"App", bundleID: "com.example.My\"App"),
            "processImagePath ENDSWITH \"/My\\\"App\" OR subsystem == \"com.example.My\\\"App\""
        )
        XCTAssertEqual(
            LogsCommand.buildPredicate(executableName: "My\\App", bundleID: "com.example"),
            "processImagePath ENDSWITH \"/My\\\\App\" OR subsystem == \"com.example\""
        )
    }

    func testPredicateHandlesExecutableNamesWithSpaces() {
        XCTAssertEqual(
            LogsCommand.buildPredicate(executableName: "My App", bundleID: "com.example.MyApp"),
            "processImagePath ENDSWITH \"/My App\" OR subsystem == \"com.example.MyApp\""
        )
    }

    func testProcessNameFromBundleID() {
        XCTAssertEqual(LogsCommand.processName(fromBundleID: "com.example.MyApp"), "MyApp")
        XCTAssertEqual(LogsCommand.processName(fromBundleID: "MyApp"), "MyApp")
        XCTAssertEqual(LogsCommand.processName(fromBundleID: "com.example.MyApp."), "MyApp")
        XCTAssertNil(LogsCommand.processName(fromBundleID: ""))
    }
}

final class InfoPlistReadingTests: XCTestCase {
    var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "nimbus-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    /// Writes `<tempDir>/<name>.app/Info.plist` and returns the .app path.
    private func makeAppBundle(name: String, plist: [String: Any]) throws -> String {
        let appPath = tempDir + "/\(name).app"
        try FileManager.default.createDirectory(atPath: appPath, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: appPath + "/Info.plist"))
        return appPath
    }

    func testExecutableNameFromInfoPlist() throws {
        let appPath = try makeAppBundle(name: "Fake", plist: [
            "CFBundleExecutable": "FakeApp",
            "CFBundleIdentifier": "com.example.Fake",
        ])

        XCTAssertEqual(SimulatorManager.executableName(appPath: appPath), "FakeApp")
        XCTAssertEqual(SimulatorManager.bundleIdentifier(appPath: appPath), "com.example.Fake")
    }

    func testExecutableNameIsNilWhenKeyMissingOrEmpty() throws {
        let missing = try makeAppBundle(name: "NoExec", plist: ["CFBundleIdentifier": "com.example.NoExec"])
        XCTAssertNil(SimulatorManager.executableName(appPath: missing))

        let empty = try makeAppBundle(name: "EmptyExec", plist: ["CFBundleExecutable": ""])
        XCTAssertNil(SimulatorManager.executableName(appPath: empty))
    }

    func testExecutableNameIsNilForMissingOrCorruptPlist() throws {
        XCTAssertNil(SimulatorManager.executableName(appPath: tempDir + "/Nope.app"))

        let corruptPath = tempDir + "/Corrupt.app"
        try FileManager.default.createDirectory(atPath: corruptPath, withIntermediateDirectories: true)
        try "this is not a plist".write(toFile: corruptPath + "/Info.plist", atomically: true, encoding: .utf8)
        XCTAssertNil(SimulatorManager.executableName(appPath: corruptPath))
        XCTAssertNil(SimulatorManager.bundleIdentifier(appPath: corruptPath))
    }

    func testExecutableNameWithNonStringValue() throws {
        let appPath = try makeAppBundle(name: "Weird", plist: ["CFBundleExecutable": 42])
        XCTAssertNil(SimulatorManager.executableName(appPath: appPath))
    }
}
