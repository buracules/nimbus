import XCTest
@testable import nimbus

/// The priority chain is the part of this feature a user can get surprised by,
/// and the shadowing notice is the correction for the one place it is
/// deliberately surprising. Both are asserted from loaded layers rather than
/// from this machine's real config files.
final class SelectionChainTests: XCTestCase {
    private func combine(
        global: NimbusConfig = .empty,
        project: NimbusConfig = .empty,
        state: NimbusConfig = .empty,
        cli: NimbusConfig = .empty
    ) -> (config: NimbusConfig, source: DeviceSource, shadowedProjectDevice: String?) {
        SelectionChain.combine(global: global, project: project, state: state, cli: cli)
    }

    // MARK: - Ordering

    func testFlagsBeatEverything() {
        let result = combine(
            global: NimbusConfig(device: "Global"),
            project: NimbusConfig(device: "Project"),
            state: NimbusConfig(device: "State"),
            cli: NimbusConfig(device: "Flag")
        )
        XCTAssertEqual(result.config.device, "Flag")
        XCTAssertEqual(result.source, .flag)
    }

    /// The whole point of the ordering: `nimbus use` in a project whose
    /// nimbus.yml names a device must not be a silent no-op.
    func testStateBeatsProjectConfig() {
        let result = combine(
            project: NimbusConfig(device: "Project"),
            state: NimbusConfig(device: "State")
        )
        XCTAssertEqual(result.config.device, "State")
        XCTAssertEqual(result.source, .state)
    }

    func testProjectConfigBeatsGlobalConfig() {
        let result = combine(
            global: NimbusConfig(device: "Global"),
            project: NimbusConfig(device: "Project")
        )
        XCTAssertEqual(result.config.device, "Project")
        XCTAssertEqual(result.source, .project)
    }

    func testGlobalConfigIsUsedWhenNothingElseNamesADevice() {
        let result = combine(global: NimbusConfig(device: "Global"))
        XCTAssertEqual(result.config.device, "Global")
        XCTAssertEqual(result.source, .global)
    }

    func testNoLayerNamingADeviceIsReportedAsUnset() {
        let result = combine(global: NimbusConfig(configuration: "Release"))
        XCTAssertNil(result.config.device)
        XCTAssertEqual(result.source, .unset)
    }

    // MARK: - The shadowing hazard

    func testShadowedProjectDeviceIsReportedWhenStateWins() {
        let result = combine(
            project: NimbusConfig(device: "iPhone 16"),
            state: NimbusConfig(device: "iPhone 17 Pro")
        )
        XCTAssertEqual(
            result.shadowedProjectDevice,
            "iPhone 16",
            "a committed device: that stops taking effect has to be visible"
        )
    }

    func testNothingIsShadowedWhenTheProjectNamesNoDevice() {
        let result = combine(state: NimbusConfig(device: "iPhone 17 Pro"))
        XCTAssertNil(result.shadowedProjectDevice)
    }

    func testNothingIsShadowedWhenAFlagOverridesBoth() {
        let result = combine(
            project: NimbusConfig(device: "iPhone 16"),
            state: NimbusConfig(device: "iPhone 17 Pro"),
            cli: NimbusConfig(device: "iPad Air")
        )
        XCTAssertNil(
            result.shadowedProjectDevice,
            "the flag is the visible cause; naming state as well would be noise"
        )
        XCTAssertEqual(result.source, .flag)
    }

    // MARK: - State touches only the device fields

    func testStateDoesNotDisturbTheOtherConfigFields() {
        let result = combine(
            global: NimbusConfig(configuration: "Release", xcbeautify: true),
            project: NimbusConfig(project: "MyApp.xcodeproj", scheme: "MyApp", configuration: "Debug"),
            state: NimbusConfig(device: "iPhone 17 Pro")
        )
        XCTAssertEqual(result.config.scheme, "MyApp")
        XCTAssertEqual(result.config.project, "MyApp.xcodeproj")
        XCTAssertEqual(result.config.configuration, "Debug")
        XCTAssertEqual(result.config.xcbeautify, true)
    }

    func testStateWithoutAnOSLeavesTheConfiguredOSAlone() {
        let result = combine(
            project: NimbusConfig(device: "iPhone 16", os: "26.2"),
            state: NimbusConfig(device: "iPhone 17 Pro")
        )
        XCTAssertEqual(result.config.device, "iPhone 17 Pro")
        XCTAssertEqual(result.config.os, "26.2", "an unpinned OS keeps tracking the layer that sets it")
    }

    func testStateOSOverridesTheProjectOS() {
        let result = combine(
            project: NimbusConfig(device: "iPhone 16", os: "26.2"),
            state: NimbusConfig(device: "iPhone 17 Pro", os: "26.4")
        )
        XCTAssertEqual(result.config.os, "26.4")
    }

    // MARK: - Source vocabulary

    func testEverySourceHasAPhrasing() {
        for source in [DeviceSource.flag, .state, .project, .global, .unset] {
            XCTAssertFalse(SelectionChain.describe(source).isEmpty)
        }
    }

    func testSourceRawValuesAreTheContract() {
        XCTAssertEqual(DeviceSource.flag.rawValue, "flag")
        XCTAssertEqual(DeviceSource.state.rawValue, "state")
        XCTAssertEqual(DeviceSource.project.rawValue, "project")
        XCTAssertEqual(DeviceSource.global.rawValue, "global")
        XCTAssertEqual(DeviceSource.unset.rawValue, "unset")
    }
}
