import XCTest
@testable import nimbus

final class DeviceIndexTests: XCTestCase {
    var tempDir: String!
    var devicesDir: String!
    var runtimesDir: String!

    override func setUpWithError() throws {
        tempDir = NSTemporaryDirectory() + "nimbus-device-index-\(UUID().uuidString)"
        devicesDir = tempDir + "/Devices"
        runtimesDir = tempDir + "/Runtimes"
        try FileManager.default.createDirectory(atPath: devicesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: runtimesDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Fixtures

    private func writeDevice(
        udid: String,
        name: String,
        runtime: String,
        state: Int,
        isDeleted: Bool = false
    ) throws {
        let dir = devicesDir + "/" + udid
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "UDID": udid,
            "name": name,
            "runtime": runtime,
            "state": state,
            "isDeleted": isDeleted,
            "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: URL(fileURLWithPath: dir + "/device.plist"))
    }

    private func writeRuntime(identifier: String, bundleName: String) throws {
        let contents = runtimesDir + "/\(bundleName).simruntime/Contents"
        try FileManager.default.createDirectory(atPath: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier],
            format: .xml,
            options: 0
        )
        try data.write(to: URL(fileURLWithPath: contents + "/Info.plist"))
    }

    private func list() -> [(runtime: String, devices: [SimulatorManager.Device])]? {
        DeviceIndex.listAvailableDevices(devicesDirectory: devicesDir, runtimeDirectories: [runtimesDir])
    }

    // MARK: - State mapping

    func testStateNamesMatchSimctlVocabulary() {
        XCTAssertEqual(DeviceIndex.stateName(0), "Creating")
        XCTAssertEqual(DeviceIndex.stateName(1), "Shutdown")
        XCTAssertEqual(DeviceIndex.stateName(2), "Booting")
        XCTAssertEqual(DeviceIndex.stateName(3), "Booted")
        XCTAssertEqual(DeviceIndex.stateName(4), "Shutting Down")
        XCTAssertEqual(DeviceIndex.stateName(99), "Unknown")
    }

    func testBootedStateFeedsIsBooted() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeDevice(udid: "A", name: "iPhone 17 Pro", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 3)
        try writeDevice(udid: "B", name: "iPhone 17 Pro Max", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)

        let groups = try XCTUnwrap(list())
        let devices = try XCTUnwrap(groups.first?.devices)
        XCTAssertEqual(devices.map(\.name), ["iPhone 17 Pro", "iPhone 17 Pro Max"])
        XCTAssertTrue(devices[0].isBooted)
        XCTAssertFalse(devices[1].isBooted)
    }

    // MARK: - Parsing

    func testParseEntryReadsTheFieldsWeUse() throws {
        let plist: [String: Any] = [
            "UDID": "64AC5E4A",
            "name": "iPhone 17 Pro",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            "state": 3,
            "isDeleted": false,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let entry = try XCTUnwrap(DeviceIndex.parseEntry(plistData: data))
        XCTAssertEqual(
            entry,
            DeviceIndex.Entry(
                udid: "64AC5E4A",
                name: "iPhone 17 Pro",
                runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                state: 3,
                isDeleted: false
            )
        )
    }

    func testParseEntryRejectsIncompletePlists() throws {
        let missingRuntime: [String: Any] = ["UDID": "A", "name": "iPhone", "state": 1]
        let data = try PropertyListSerialization.data(fromPropertyList: missingRuntime, format: .binary, options: 0)
        XCTAssertNil(DeviceIndex.parseEntry(plistData: data))
        XCTAssertNil(DeviceIndex.parseEntry(plistData: Data("not a plist".utf8)))
        XCTAssertNil(DeviceIndex.parseEntry(plistData: Data()))
    }

    // MARK: - Runtime discovery

    func testInstalledRuntimeIdentifiersReadsBundleIdentifiers() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", bundleName: "iOS 27.0")
        XCTAssertEqual(
            DeviceIndex.installedRuntimeIdentifiers(in: [runtimesDir]),
            [
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            ]
        )
    }

    func testInstalledRuntimeIdentifiersIgnoresMissingDirectoriesAndJunk() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        // A non-runtime directory alongside a real one must not upset the scan.
        try FileManager.default.createDirectory(atPath: runtimesDir + "/notes.txt", withIntermediateDirectories: true)
        XCTAssertEqual(
            DeviceIndex.installedRuntimeIdentifiers(in: [runtimesDir, tempDir + "/does-not-exist"]),
            ["com.apple.CoreSimulator.SimRuntime.iOS-26-5"]
        )
    }

    func testExpandMountContainerAppendsSuffixToEachChild() throws {
        let container = tempDir + "/Volumes"
        try FileManager.default.createDirectory(atPath: container + "/iOS_23F77", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: container + "/iOS_24A5355p", withIntermediateDirectories: true)

        XCTAssertEqual(
            DeviceIndex.expandMountContainer(container, suffix: "Profiles/Runtimes"),
            [
                container + "/iOS_23F77/Profiles/Runtimes",
                container + "/iOS_24A5355p/Profiles/Runtimes",
            ]
        )
        XCTAssertEqual(DeviceIndex.expandMountContainer(tempDir + "/nope", suffix: "x"), [])
    }

    // MARK: - Enumeration

    func testDevicesWithAnUninstalledRuntimeAreOmitted() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeDevice(udid: "A", name: "Installed", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        try writeDevice(udid: "B", name: "Orphan", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", state: 1)

        let groups = try XCTUnwrap(list())
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].runtime, "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
        XCTAssertEqual(groups[0].devices.map(\.name), ["Installed"])
        XCTAssertTrue(groups[0].devices.allSatisfy { $0.isAvailable })
    }

    func testDeletedDevicesAreOmitted() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeDevice(udid: "A", name: "Live", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        try writeDevice(udid: "B", name: "Tombstone", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1, isDeleted: true)

        let groups = try XCTUnwrap(list())
        XCTAssertEqual(groups.flatMap { $0.devices }.map(\.name), ["Live"])
    }

    func testGroupsAndDevicesAreOrderedDeterministically() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-5", bundleName: "iOS 18.5")
        try writeDevice(udid: "C", name: "iPhone 17 Pro Max", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        try writeDevice(udid: "A", name: "iPhone 17 Pro", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        try writeDevice(udid: "B", name: "iPhone SE", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-5", state: 1)

        let groups = try XCTUnwrap(list())
        XCTAssertEqual(groups.map(\.runtime), [
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        ])
        XCTAssertEqual(groups[1].devices.map(\.name), ["iPhone 17 Pro", "iPhone 17 Pro Max"])
    }

    func testNonDeviceDirectoriesAreSkipped() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeDevice(udid: "A", name: "Live", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        // device_set.plist and friends sit next to the device directories.
        try Data("x".utf8).write(to: URL(fileURLWithPath: devicesDir + "/device_set.plist"))
        try FileManager.default.createDirectory(atPath: devicesDir + "/.Trash", withIntermediateDirectories: true)

        XCTAssertEqual(try XCTUnwrap(list()).flatMap { $0.devices }.map(\.name), ["Live"])
    }

    // MARK: - Fallback conditions

    func testMissingDevicesDirectoryFallsBack() {
        XCTAssertNil(
            DeviceIndex.listAvailableDevices(
                devicesDirectory: tempDir + "/does-not-exist",
                runtimeDirectories: [runtimesDir]
            )
        )
    }

    func testNoDiscoverableRuntimesFallsBack() throws {
        try writeDevice(udid: "A", name: "Live", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        XCTAssertNil(list())
    }

    func testCorruptDevicePlistFallsBack() throws {
        try writeRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", bundleName: "iOS 26.5")
        try writeDevice(udid: "A", name: "Live", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", state: 1)
        let corrupt = devicesDir + "/B"
        try FileManager.default.createDirectory(atPath: corrupt, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: URL(fileURLWithPath: corrupt + "/device.plist"))

        XCTAssertNil(list())
    }

    // MARK: - Equivalence with simctl

    /// The whole fast path rests on the claim that reading CoreSimulator's
    /// files answers the same question `simctl list devices --json` does. That
    /// claim is about this machine's real device set, so assert it here.
    ///
    /// State is deliberately excluded: the plist is written after a transition
    /// completes, so a device booting or shutting down while this runs would
    /// legitimately disagree. Identity and availability must not.
    func testIndexAgreesWithSimctlOnIdentityAndAvailability() throws {
        guard let indexed = DeviceIndex.listAvailableDevices() else {
            throw XCTSkip("CoreSimulator device index unavailable on this machine")
        }
        guard let simctlGroups = try? SimulatorManager.listDevices() else {
            throw XCTSkip("simctl unavailable on this machine")
        }

        func identity(_ groups: [(runtime: String, devices: [SimulatorManager.Device])]) -> Set<String> {
            Set(groups.flatMap { group in
                group.devices.map { "\(group.runtime)|\($0.udid)|\($0.name)" }
            })
        }

        XCTAssertEqual(
            identity(indexed),
            identity(simctlGroups),
            "CoreSimulator index and simctl disagree about which simulators are available"
        )
    }
}
