import XCTest
@testable import nimbus

final class SimCommandTests: XCTestCase {

    // MARK: - Status bar flag mapping

    func testStatusBarOverridesUseSimctlFlagNames() {
        XCTAssertEqual(
            SimStatusBarCommand.overrideArguments(
                time: "9:41",
                batteryLevel: 100,
                batteryState: "charged",
                wifiBars: 3,
                cellularBars: 4,
                dataNetwork: "5g",
                operatorName: "Nimbus"
            ),
            [
                "--time", "9:41",
                "--batteryState", "charged",
                "--batteryLevel", "100",
                "--dataNetwork", "5g",
                "--wifiBars", "3",
                "--cellularBars", "4",
                "--operatorName", "Nimbus",
            ]
        )
    }

    func testStatusBarOmitsFlagsThatWereNotAsis() {
        XCTAssertEqual(SimStatusBarCommand.overrideArguments(time: "9:41"), ["--time", "9:41"])
        XCTAssertEqual(SimStatusBarCommand.overrideArguments(batteryLevel: 0), ["--batteryLevel", "0"])
        XCTAssertEqual(SimStatusBarCommand.overrideArguments(), [])
    }

    // MARK: - Coordinates

    func testCoordinatesParse() throws {
        let point = try XCTUnwrap(SimLocationCommand.parseCoordinates("37.3349,-122.0090"))
        XCTAssertEqual(point.latitude, 37.3349, accuracy: 0.00001)
        XCTAssertEqual(point.longitude, -122.0090, accuracy: 0.00001)
    }

    func testCoordinatesTolerateSpacesAndIntegers() throws {
        let point = try XCTUnwrap(SimLocationCommand.parseCoordinates(" 51 , 0 "))
        XCTAssertEqual(point.latitude, 51)
        XCTAssertEqual(point.longitude, 0)
    }

    func testCoordinatesRejectGarbageAndOutOfRange() {
        XCTAssertNil(SimLocationCommand.parseCoordinates("37.3349"))
        XCTAssertNil(SimLocationCommand.parseCoordinates("north,west"))
        XCTAssertNil(SimLocationCommand.parseCoordinates(""))
        XCTAssertNil(SimLocationCommand.parseCoordinates("37,-122,5"))
        XCTAssertNil(SimLocationCommand.parseCoordinates("91,0"), "latitude above 90")
        XCTAssertNil(SimLocationCommand.parseCoordinates("0,181"), "longitude above 180")
    }

    // MARK: - Paths

    func testRelativePathsBecomeAbsolute() {
        let absolute = SimPaths.absolute("shot.png")
        XCTAssertTrue(absolute.hasPrefix("/"))
        XCTAssertTrue(absolute.hasSuffix("/shot.png"))
    }

    func testAbsoluteAndTildePathsAreKept() {
        XCTAssertEqual(SimPaths.absolute("/tmp/shot.png"), "/tmp/shot.png")
        XCTAssertTrue(SimPaths.absolute("~/shot.png").hasPrefix("/"))
        XCTAssertFalse(SimPaths.absolute("~/shot.png").contains("~"))
    }

    func testDefaultPathsAreTimestampedAndAbsolute() {
        let path = SimPaths.defaultPath(prefix: "screenshot", extension: "png")
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertTrue(path.contains("nimbus-screenshot-"))
        XCTAssertTrue(path.hasSuffix(".png"))
    }
}
