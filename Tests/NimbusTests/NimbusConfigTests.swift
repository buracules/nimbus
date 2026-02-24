import XCTest
@testable import nimbus

final class NimbusConfigTests: XCTestCase {
    func testEmptyConfig() {
        let config = NimbusConfig.empty
        XCTAssertNil(config.project)
        XCTAssertNil(config.workspace)
        XCTAssertNil(config.scheme)
        XCTAssertNil(config.device)
        XCTAssertNil(config.os)
        XCTAssertNil(config.configuration)
        XCTAssertNil(config.xcbeautify)
    }

    func testMerging() {
        let base = NimbusConfig(
            project: "Base.xcodeproj",
            workspace: nil,
            scheme: "Base",
            device: "iPhone 16",
            os: "18.0",
            configuration: "Debug",
            xcbeautify: true
        )
        let override = NimbusConfig(
            project: nil,
            workspace: nil,
            scheme: "Override",
            device: nil,
            os: nil,
            configuration: "Release",
            xcbeautify: nil
        )

        let merged = base.merging(with: override)

        XCTAssertEqual(merged.project, "Base.xcodeproj")
        XCTAssertEqual(merged.scheme, "Override")
        XCTAssertEqual(merged.device, "iPhone 16")
        XCTAssertEqual(merged.os, "18.0")
        XCTAssertEqual(merged.configuration, "Release")
        XCTAssertEqual(merged.xcbeautify, true)
    }

    func testMergingOverridesNilWithValue() {
        let base = NimbusConfig.empty
        let override = NimbusConfig(
            project: nil,
            workspace: "App.xcworkspace",
            scheme: "App",
            device: nil,
            os: nil,
            configuration: nil,
            xcbeautify: nil
        )

        let merged = base.merging(with: override)
        XCTAssertEqual(merged.workspace, "App.xcworkspace")
        XCTAssertEqual(merged.scheme, "App")
    }

    func testToYAMLWithProject() {
        let config = NimbusConfig(
            project: "MyApp.xcodeproj",
            workspace: nil,
            scheme: "MyApp",
            device: "iPhone 17",
            os: "26.2",
            configuration: "Debug",
            xcbeautify: true
        )

        let yaml = config.toYAML()
        XCTAssertTrue(yaml.contains("project: MyApp.xcodeproj"))
        XCTAssertTrue(yaml.contains("scheme: MyApp"))
        XCTAssertTrue(yaml.contains("device: \"iPhone 17\""))
        XCTAssertTrue(yaml.contains("os: \"26.2\""))
        XCTAssertTrue(yaml.contains("configuration: Debug"))
        XCTAssertTrue(yaml.contains("xcbeautify: true"))
    }

    func testToYAMLPrefersWorkspaceOverProject() {
        let config = NimbusConfig(
            project: "MyApp.xcodeproj",
            workspace: "MyApp.xcworkspace",
            scheme: nil,
            device: nil,
            os: nil,
            configuration: nil,
            xcbeautify: nil
        )

        let yaml = config.toYAML()
        XCTAssertTrue(yaml.contains("workspace: MyApp.xcworkspace"))
        XCTAssertFalse(yaml.contains("project:"))
    }

    func testEquatable() {
        let a = NimbusConfig(project: "A.xcodeproj", workspace: nil, scheme: "A",
                             device: nil, os: nil, configuration: nil, xcbeautify: nil)
        let b = NimbusConfig(project: "A.xcodeproj", workspace: nil, scheme: "A",
                             device: nil, os: nil, configuration: nil, xcbeautify: nil)
        XCTAssertEqual(a, b)
    }
}
