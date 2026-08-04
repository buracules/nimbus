import XCTest
@testable import nimbus

/// The device-choosing rules every command depends on. These became testable
/// once lookup stopped enumerating simulators itself and started taking the
/// catalog as an argument.
final class DeviceLookupTests: XCTestCase {
    typealias Group = (runtime: String, devices: [SimulatorManager.Device])

    private func device(_ name: String, udid: String, booted: Bool = false) -> SimulatorManager.Device {
        SimulatorManager.Device(
            udid: udid,
            name: name,
            state: booted ? "Booted" : "Shutdown",
            isAvailable: true,
            availabilityError: nil
        )
    }

    private let iOS18 = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
    private let iOS26 = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"

    private func catalog(bootedIn bootedRuntime: String? = nil) -> [Group] {
        [
            (runtime: iOS18, devices: [
                device("iPhone SE", udid: "se-18", booted: bootedRuntime == iOS18),
                device("iPhone 17 Pro", udid: "pro-18"),
            ]),
            (runtime: iOS26, devices: [
                device("iPhone 17 Pro", udid: "pro-26", booted: bootedRuntime == iOS26),
                device("iPhone 17 Pro Max", udid: "max-26"),
            ]),
        ]
    }

    // MARK: - findDevice

    func testFindDeviceMatchesByNameAcrossRuntimes() throws {
        let match = try XCTUnwrap(SimulatorManager.findDevice(in: catalog(), name: "iPhone 17 Pro Max"))
        XCTAssertEqual(match.device.udid, "max-26")
        XCTAssertEqual(match.runtime, iOS26)
    }

    func testFindDeviceHonoursTheOSFilter() throws {
        let match = try XCTUnwrap(SimulatorManager.findDevice(in: catalog(), name: "iPhone 17 Pro", os: "26.5"))
        XCTAssertEqual(match.device.udid, "pro-26")
        XCTAssertNil(SimulatorManager.findDevice(in: catalog(), name: "iPhone SE", os: "26.5"))
    }

    func testFindDeviceReturnsNilForAnUnknownName() {
        XCTAssertNil(SimulatorManager.findDevice(in: catalog(), name: "iPhone 4"))
    }

    // MARK: - findDeviceWithFallback priority

    func testExactNameAndOSWinOverABootedDevice() throws {
        let match = try XCTUnwrap(
            SimulatorManager.findDeviceWithFallback(in: catalog(bootedIn: iOS18), name: "iPhone 17 Pro Max", os: nil)
        )
        XCTAssertEqual(match.device.udid, "max-26")
    }

    func testABootedDeviceMatchingTheRequestedOSComesNext() throws {
        let match = try XCTUnwrap(
            SimulatorManager.findDeviceWithFallback(in: catalog(bootedIn: iOS26), name: nil, os: "26.5")
        )
        XCTAssertEqual(match.device.udid, "pro-26")
    }

    func testAnyBootedDeviceBeatsAnUnbootedOne() throws {
        let match = try XCTUnwrap(
            SimulatorManager.findDeviceWithFallback(in: catalog(bootedIn: iOS26), name: nil, os: nil)
        )
        XCTAssertEqual(match.device.udid, "pro-26")
    }

    func testUnknownNameFallsBackToTheFirstDeviceOfTheRequestedOS() throws {
        let match = try XCTUnwrap(
            SimulatorManager.findDeviceWithFallback(in: catalog(), name: "iPhone 17", os: "26.5")
        )
        XCTAssertEqual(match.device.udid, "pro-26")
    }

    func testWithNothingBootedTheFirstDeviceOfTheFirstRuntimeWins() throws {
        let match = try XCTUnwrap(
            SimulatorManager.findDeviceWithFallback(in: catalog(), name: nil, os: nil)
        )
        XCTAssertEqual(match.device.udid, "se-18")
    }

    func testEmptyCatalogResolvesToNothing() {
        XCTAssertNil(SimulatorManager.findDeviceWithFallback(in: [], name: "iPhone 17 Pro", os: nil))
    }

    // MARK: - suggestDevices

    func testSuggestionsComeFromTheCatalog() {
        let suggestions = SimulatorManager.suggestDevices(in: catalog(), for: "iPhone 17 Por")
        XCTAssertTrue(suggestions.contains("iPhone 17 Pro"), "got \(suggestions)")
    }

    func testSuggestionsRespectTheOSFilter() {
        let suggestions = SimulatorManager.suggestDevices(in: catalog(), for: "iPhone SE", os: "26.5")
        XCTAssertFalse(suggestions.contains("iPhone SE"))
    }

    func testNonsenseQueryYieldsNoSuggestions() {
        XCTAssertEqual(SimulatorManager.suggestDevices(in: catalog(), for: "zzzzzzzzzz"), [])
    }
}
