import XCTest
@testable import nimbus

/// Project identity is the key everything per-project is filed under, so getting
/// it wrong does not fail loudly — it silently remembers the wrong project.
/// These fix the two things that would produce that: the walk, and the
/// precedence between the two markers.
final class ProjectIdentityTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = resolved(NSTemporaryDirectory() + "nimbus-identity-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    /// `NSTemporaryDirectory()` hands back a `/var/...` path that is really
    /// `/private/var/...`, which is the exact hazard `projectRoot` resolves.
    private func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func makeDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func write(_ contents: String, to path: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - The walk

    func testWorkspaceProjectIsFoundFromASubdirectory() throws {
        // The owner's case: a real project that deliberately has no nimbus.yml.
        try makeDirectory(tempDir + "/Pegasus.xcworkspace")
        let nested = tempDir + "/Sources/Feature"
        try makeDirectory(nested)

        XCTAssertEqual(ProjectIdentity.projectRoot(from: nested), tempDir)
        XCTAssertEqual(
            ProjectIdentity.key(for: ProjectIdentity.projectRoot(from: nested)),
            ProjectIdentity.key(for: ProjectIdentity.projectRoot(from: tempDir)),
            "a subdirectory must key to the same project as the root"
        )
    }

    func testXcodeprojIsFoundFromASubdirectory() throws {
        try makeDirectory(tempDir + "/MyApp.xcodeproj")
        let nested = tempDir + "/App/Views"
        try makeDirectory(nested)

        XCTAssertEqual(ProjectIdentity.projectRoot(from: nested), tempDir)
    }

    func testConfigFileIsFoundFromASubdirectory() throws {
        try write("scheme: MyApp\n", to: tempDir + "/nimbus.yml")
        let nested = tempDir + "/a/b/c"
        try makeDirectory(nested)

        XCTAssertEqual(ProjectIdentity.projectRoot(from: nested), tempDir)
    }

    func testFallsBackToTheDirectoryItselfWhenNothingMarksAProject() throws {
        let nested = tempDir + "/nowhere"
        try makeDirectory(nested)

        XCTAssertEqual(ProjectIdentity.projectRoot(from: nested), nested)
    }

    // MARK: - Precedence between the two markers

    func testNearestMarkerWinsWhenAProjectFileIsBelowTheConfigFile() throws {
        // A monorepo: one shared nimbus.yml on top, an app below it. The app is
        // the project, so two apps under one config get two pinned simulators.
        try write("configuration: Debug\n", to: tempDir + "/nimbus.yml")
        let app = tempDir + "/apps/Checkout"
        try makeDirectory(app + "/Checkout.xcodeproj")
        let nested = app + "/Sources"
        try makeDirectory(nested)

        XCTAssertEqual(ProjectIdentity.projectRoot(from: nested), app)
        XCTAssertEqual(ProjectIdentity.projectRoot(from: app), app)
    }

    func testNearestMarkerWinsWhenAConfigFileIsBelowTheProjectFile() throws {
        try makeDirectory(tempDir + "/MyApp.xcodeproj")
        let inner = tempDir + "/Packages/Design"
        try makeDirectory(inner)
        try write("scheme: Design\n", to: inner + "/nimbus.yml")

        XCTAssertEqual(
            ProjectIdentity.projectRoot(from: inner),
            inner,
            "a deliberately placed nimbus.yml marks its own project"
        )
        XCTAssertEqual(ProjectIdentity.projectRoot(from: tempDir), tempDir)
    }

    func testTwoSiblingProjectsUnderOneConfigGetDifferentKeys() throws {
        try write("configuration: Debug\n", to: tempDir + "/nimbus.yml")
        let first = tempDir + "/apps/One"
        let second = tempDir + "/apps/Two"
        try makeDirectory(first + "/One.xcodeproj")
        try makeDirectory(second + "/Two.xcodeproj")

        XCTAssertNotEqual(
            ProjectIdentity.key(for: ProjectIdentity.projectRoot(from: first)),
            ProjectIdentity.key(for: ProjectIdentity.projectRoot(from: second))
        )
    }

    func testBothMarkersInOneDirectoryAgree() throws {
        try write("scheme: MyApp\n", to: tempDir + "/nimbus.yml")
        try makeDirectory(tempDir + "/MyApp.xcodeproj")

        XCTAssertEqual(ProjectIdentity.projectRoot(from: tempDir), tempDir)
    }

    // MARK: - Symlinks

    func testSymlinkedPathsProduceOneKey() throws {
        try makeDirectory(tempDir + "/MyApp.xcodeproj")
        let link = NSTemporaryDirectory() + "nimbus-link-\(UUID().uuidString)"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: tempDir)
        defer { try? FileManager.default.removeItem(atPath: link) }

        XCTAssertEqual(ProjectIdentity.projectRoot(from: link), tempDir)
        XCTAssertEqual(
            ProjectIdentity.key(for: ProjectIdentity.projectRoot(from: link)),
            ProjectIdentity.key(for: ProjectIdentity.projectRoot(from: tempDir))
        )
    }

    // MARK: - The project file handed to xcodebuild

    func testProjectFileIsAbsoluteAndComesFromTheProjectRoot() throws {
        try makeDirectory(tempDir + "/MyApp.xcworkspace")
        let nested = tempDir + "/Sources"
        try makeDirectory(nested)

        let detected = ProjectIdentity.projectFile(from: nested)
        XCTAssertEqual(detected?.flag, "-workspace")
        XCTAssertEqual(detected?.value, tempDir + "/MyApp.xcworkspace")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: detected?.value ?? ""),
            "the path handed to xcodebuild has to exist regardless of the caller's cwd"
        )
    }

    func testProjectFileIsNilWhenTheRootHasNoXcodeProject() throws {
        try write("scheme: MyApp\n", to: tempDir + "/nimbus.yml")
        XCTAssertNil(ProjectIdentity.projectFile(from: tempDir))
    }

    // MARK: - Keys

    func testKeyIsAStableHexDigest() {
        let key = ProjectIdentity.key(for: "/Users/someone/Projects/App")
        XCTAssertEqual(key.count, 64)
        XCTAssertTrue(key.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(key, ProjectIdentity.key(for: "/Users/someone/Projects/App"))
        XCTAssertNotEqual(key, ProjectIdentity.key(for: "/Users/someone/Projects/App2"))
    }

    func testKeySurvivesSpacesAndNonASCII() {
        let key = ProjectIdentity.key(for: "/Users/me/Side Stuff/nímbus")
        XCTAssertEqual(key.count, 64)
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains(" "))
    }
}
