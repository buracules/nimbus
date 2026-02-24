import XCTest
@testable import nimbus

final class ProjectDetectorTests: XCTestCase {
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

    func testFindProjectsEmpty() {
        let projects = ProjectDetector.findProjects(in: tempDir)
        XCTAssertTrue(projects.isEmpty)
    }

    func testFindProjects() throws {
        // Create fake .xcodeproj directories
        try FileManager.default.createDirectory(
            atPath: tempDir + "/MyApp.xcodeproj",
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: tempDir + "/Other.xcodeproj",
            withIntermediateDirectories: true
        )

        let projects = ProjectDetector.findProjects(in: tempDir)
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.contains("MyApp.xcodeproj"))
        XCTAssertTrue(projects.contains("Other.xcodeproj"))
    }

    func testFindWorkspacesExcludesProjectWorkspace() throws {
        // Create a real workspace and a project.xcworkspace
        try FileManager.default.createDirectory(
            atPath: tempDir + "/MyApp.xcworkspace",
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: tempDir + "/project.xcworkspace",
            withIntermediateDirectories: true
        )

        let workspaces = ProjectDetector.findWorkspaces(in: tempDir)
        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces.first, "MyApp.xcworkspace")
    }

    func testDetectProjectFilePrefersWorkspace() throws {
        try FileManager.default.createDirectory(
            atPath: tempDir + "/MyApp.xcworkspace",
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: tempDir + "/MyApp.xcodeproj",
            withIntermediateDirectories: true
        )

        let result = ProjectDetector.detectProjectFile(in: tempDir)
        XCTAssertEqual(result?.flag, "-workspace")
        XCTAssertEqual(result?.value, "MyApp.xcworkspace")
    }

    func testDetectProjectFileFallsBackToProject() throws {
        try FileManager.default.createDirectory(
            atPath: tempDir + "/MyApp.xcodeproj",
            withIntermediateDirectories: true
        )

        let result = ProjectDetector.detectProjectFile(in: tempDir)
        XCTAssertEqual(result?.flag, "-project")
        XCTAssertEqual(result?.value, "MyApp.xcodeproj")
    }

    func testDetectProjectFileReturnsNilWhenEmpty() {
        let result = ProjectDetector.detectProjectFile(in: tempDir)
        XCTAssertNil(result)
    }

    func testParseSchemesFromWorkspaceJSON() {
        let json = """
        {
          "workspace": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests", "MyAppUITests"]
          }
        }
        """
        let schemes = ProjectDetector.parseSchemes(from: json)
        XCTAssertEqual(schemes, ["MyApp", "MyAppTests", "MyAppUITests"])
    }

    func testParseSchemesFromProjectJSON() {
        let json = """
        {
          "project": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests"]
          }
        }
        """
        let schemes = ProjectDetector.parseSchemes(from: json)
        XCTAssertEqual(schemes, ["MyApp", "MyAppTests"])
    }

    func testParseSchemesInvalidJSON() {
        let schemes = ProjectDetector.parseSchemes(from: "not json")
        XCTAssertTrue(schemes.isEmpty)
    }
}
