import XCTest
@testable import nimbus

/// The envelope is a published contract. These tests pin its shape and its
/// error codes, because a caller branching on `error.code` breaks silently if
/// either drifts.
final class CommandOutputTests: XCTestCase {
    private func decode(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Shape

    func testSuccessEnvelopeCarriesDataAndNoError() throws {
        struct Payload: Encodable { let scheme: String }
        let json = try CommandOutput.render(command: "build", data: Payload(scheme: "MyApp"))
        let object = try decode(json)

        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual(object["command"] as? String, "build")
        XCTAssertNil(object["error"], "a success envelope must not carry an error key")
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["scheme"] as? String, "MyApp")
    }

    func testFailureEnvelopeCarriesErrorAndNoData() throws {
        let failure = NimbusFailure(.buildFailed, "Build failed after 2.0s", exitCode: 65)
        let json = try CommandOutput.render(command: "build", failure: failure)
        let object = try decode(json)

        XCTAssertEqual(object["ok"] as? Bool, false)
        XCTAssertEqual(object["command"] as? String, "build")
        XCTAssertNil(object["data"], "a failure envelope must not carry a data key")

        let error = try XCTUnwrap(object["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "build_failed")
        XCTAssertEqual(error["message"] as? String, "Build failed after 2.0s")
        XCTAssertEqual(error["exitCode"] as? Int, 65)
    }

    func testFailureOmitsExitCodeAndDiagnosticsWhenThereAreNone() throws {
        let json = try CommandOutput.render(
            command: "sim location",
            failure: NimbusFailure(.invalidArguments, "Could not read 'x' as lat,lon.")
        )
        let error = try XCTUnwrap(try decode(json)["error"] as? [String: Any])

        XCTAssertNil(error["exitCode"])
        XCTAssertNil(error["diagnostics"], "an empty diagnostics list is absent, not empty")
    }

    func testFailureCarriesDiagnosticsWhenTheToolExplainedItself() throws {
        let failure = NimbusFailure(
            .buildFailed,
            "Build failed after 2.0s",
            exitCode: 65,
            diagnostics: ["ContentView.swift:12:3: error: cannot convert value of type 'String' to 'Int'"]
        )
        let json = try CommandOutput.render(command: "build", failure: failure)
        let error = try XCTUnwrap(try decode(json)["error"] as? [String: Any])
        let diagnostics = try XCTUnwrap(error["diagnostics"] as? [String])

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].contains("cannot convert value"))
    }

    func testPathsAreNotEscaped() throws {
        struct Payload: Encodable { let path: String }
        let json = try CommandOutput.render(command: "sim screenshot", data: Payload(path: "/tmp/a.png"))
        XCTAssertTrue(json.contains("/tmp/a.png"), "file paths must stay readable, not become \\/tmp\\/a.png")
    }

    // MARK: - Codes

    func testEveryErrorCodeIsLowerSnakeCase() {
        let codes: [NimbusErrorCode] = [
            .buildFailed, .testFailed, .cleanFailed, .noSimulators, .noDeviceSelected,
            .schemeUnknown, .appBundleNotFound, .bundleIdentifierUnknown, .xcodebuildNotFound,
            .configExists, .invalidArguments, .fileNotFound, .commandFailed, .parseError,
            .configError, .notFound, .unsupportedOutputMode, .internalError,
        ]
        for code in codes {
            let raw = code.rawValue
            XCTAssertFalse(raw.isEmpty)
            XCTAssertTrue(
                raw.allSatisfy { $0.isLowercase || $0 == "_" },
                "\(raw) is not lower_snake_case — codes are the part callers match on"
            )
        }
    }

    func testCoreErrorsMapOntoStableCodes() {
        XCTAssertEqual(NimbusErrorCode(NimbusError.commandFailed("simctl boot", "boom")), .commandFailed)
        XCTAssertEqual(NimbusErrorCode(NimbusError.parseError("bad json")), .parseError)
        XCTAssertEqual(NimbusErrorCode(NimbusError.configError("bad yaml")), .configError)
        XCTAssertEqual(NimbusErrorCode(NimbusError.notFound("xcodebuild")), .notFound)
    }

    // MARK: - Classification

    func testAFailureThrownByACommandIsCarriedThroughUnchanged() {
        let original = NimbusFailure(.appBundleNotFound, "Built app not found.")
        let classified = NimbusFailure(from: original)

        XCTAssertEqual(classified.code, .appBundleNotFound)
        XCTAssertEqual(classified.message, "Built app not found.")
    }

    func testACoreErrorIsClassifiedWithItsOwnDescription() {
        let classified = NimbusFailure(from: NimbusError.commandFailed("simctl boot", "device busy"))

        XCTAssertEqual(classified.code, .commandFailed)
        XCTAssertEqual(classified.message, "simctl boot failed: device busy")
    }

    func testAnythingElseIsInternalRatherThanMisreported() {
        struct Surprise: Error {}
        XCTAssertEqual(NimbusFailure(from: Surprise()).code, .internalError)
    }
}
