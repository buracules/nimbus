import XCTest
@testable import nimbus

final class XcodeBuildRunnerTests: XCTestCase {

    // MARK: - parseBuiltProductPath(fromJSON:)

    /// Shape of a real `xcodebuild -showBuildSettings -json` payload, trimmed
    /// to the keys we read.
    private let appOnlyPayload = """
    [
      {
        "action" : "build",
        "target" : "MyApp",
        "buildSettings" : {
          "CONFIGURATION" : "Debug",
          "WRAPPER_NAME" : "MyApp.app",
          "TARGET_BUILD_DIR" : "/Users/dev/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/Debug-iphonesimulator",
          "CODESIGNING_FOLDER_PATH" : "/Users/dev/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/Debug-iphonesimulator/MyApp.app"
        }
      }
    ]
    """

    func testParsesAppTargetPath() {
        XCTAssertEqual(
            XcodeBuildRunner.parseBuiltProductPath(fromJSON: appOnlyPayload),
            "/Users/dev/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/Debug-iphonesimulator/MyApp.app"
        )
    }

    func testSkipsNonAppTargets() {
        let json = """
        [
          {
            "action" : "build",
            "target" : "MyAppTests",
            "buildSettings" : {
              "WRAPPER_NAME" : "MyAppTests.xctest",
              "TARGET_BUILD_DIR" : "/build/Debug-iphonesimulator"
            }
          },
          {
            "action" : "build",
            "target" : "SharedKit",
            "buildSettings" : {
              "WRAPPER_NAME" : "SharedKit.framework",
              "TARGET_BUILD_DIR" : "/build/Debug-iphonesimulator"
            }
          },
          {
            "action" : "build",
            "target" : "MyApp",
            "buildSettings" : {
              "WRAPPER_NAME" : "MyApp.app",
              "TARGET_BUILD_DIR" : "/build/Debug-iphonesimulator"
            }
          }
        ]
        """
        XCTAssertEqual(
            XcodeBuildRunner.parseBuiltProductPath(fromJSON: json),
            "/build/Debug-iphonesimulator/MyApp.app"
        )
    }

    func testFallsBackToCodesigningFolderPathWhenBuildDirMissing() {
        let json = """
        [
          {
            "target" : "MyApp",
            "buildSettings" : {
              "WRAPPER_NAME" : "MyApp.app",
              "CODESIGNING_FOLDER_PATH" : "/build/Debug-iphonesimulator/MyApp.app"
            }
          }
        ]
        """
        XCTAssertEqual(
            XcodeBuildRunner.parseBuiltProductPath(fromJSON: json),
            "/build/Debug-iphonesimulator/MyApp.app"
        )
    }

    func testTolerantOfNoiseBeforeTheJSONArray() {
        let json = """
        note: Using new build system
        warning: something xcodebuild wanted to say
        \(appOnlyPayload)
        """
        XCTAssertEqual(
            XcodeBuildRunner.parseBuiltProductPath(fromJSON: json),
            "/Users/dev/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/Debug-iphonesimulator/MyApp.app"
        )
    }

    func testReturnsNilWhenNoAppTargetPresent() {
        let json = """
        [
          {
            "target" : "SharedKit",
            "buildSettings" : { "WRAPPER_NAME" : "SharedKit.framework", "TARGET_BUILD_DIR" : "/build" }
          }
        ]
        """
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: json))
    }

    func testReturnsNilForEmptyOrMalformedPayloads() {
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: ""))
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: "[]"))
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: "not json at all"))
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: "[{\"target\": \"MyApp\"}]"))
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: "{\"buildSettings\": {}}"))
        XCTAssertNil(XcodeBuildRunner.parseBuiltProductPath(fromJSON: "[{\"buildSettings\": {\"WRAPPER_NAME\": \"MyApp.app\"}}]"))
    }

    // MARK: - Destination / arguments

    private func makeConfig(
        project: String? = "MyApp.xcodeproj",
        scheme: String? = "MyApp",
        device: String? = nil,
        os: String? = nil,
        configuration: String? = "Debug"
    ) -> NimbusConfig {
        NimbusConfig(
            project: project,
            workspace: nil,
            scheme: scheme,
            device: device,
            os: os,
            configuration: configuration,
            xcbeautify: nil
        )
    }

    func testResolvedDestinationPrefersUDID() {
        let runner = XcodeBuildRunner(
            config: makeConfig(device: "iPhone 17", os: "26.2"),
            verbose: false,
            destinationUDID: "ABC-123"
        )
        XCTAssertEqual(runner.resolvedDestination, "platform=iOS Simulator,id=ABC-123")
    }

    func testResolvedDestinationFallsBackToNameAndOS() {
        let runner = XcodeBuildRunner(config: makeConfig(device: "iPhone 17", os: "26.2"), verbose: false)
        XCTAssertEqual(runner.resolvedDestination, "platform=iOS Simulator,name=iPhone 17,OS=26.2")
    }

    func testResolvedDestinationIsNilWithoutDeviceOrOS() {
        let runner = XcodeBuildRunner(config: makeConfig(), verbose: false)
        XCTAssertNil(runner.resolvedDestination)
    }

    func testBuildArgumentsAppendActionToCommonArguments() throws {
        let runner = XcodeBuildRunner(config: makeConfig(), verbose: false, destinationUDID: "ABC-123")
        let common = runner.commonArguments(destination: runner.resolvedDestination)
        let args = try runner.buildArguments(for: .build, destination: runner.resolvedDestination)

        XCTAssertEqual(args, common + ["build"])
        XCTAssertEqual(
            args,
            [
                "-project", "MyApp.xcodeproj",
                "-scheme", "MyApp",
                "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,id=ABC-123",
                "build",
            ]
        )
    }
}
