import XCTest
@testable import nimbus

final class ConfigLoaderTests: XCTestCase {
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

    func testLoadMissingFile() throws {
        let config = try ConfigLoader.load(from: tempDir)
        XCTAssertEqual(config, NimbusConfig.empty)
    }

    func testLoadValidYAML() throws {
        let yaml = """
        project: MyApp.xcodeproj
        scheme: MyApp
        device: "iPhone 17"
        os: "26.2"
        configuration: Debug
        xcbeautify: true
        """
        let path = tempDir + "/nimbus.yml"
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: tempDir)

        XCTAssertEqual(config.project, "MyApp.xcodeproj")
        XCTAssertEqual(config.scheme, "MyApp")
        XCTAssertEqual(config.device, "iPhone 17")
        XCTAssertEqual(config.os, "26.2")
        XCTAssertEqual(config.configuration, "Debug")
        XCTAssertEqual(config.xcbeautify, true)
    }

    func testLoadWorkspaceConfig() throws {
        let yaml = """
        workspace: MyApp.xcworkspace
        scheme: MyApp
        """
        let path = tempDir + "/nimbus.yml"
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: tempDir)

        XCTAssertEqual(config.workspace, "MyApp.xcworkspace")
        XCTAssertNil(config.project)
        XCTAssertEqual(config.scheme, "MyApp")
    }

    func testLoadPartialConfig() throws {
        let yaml = "scheme: JustAScheme\n"
        let path = tempDir + "/nimbus.yml"
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: tempDir)

        XCTAssertEqual(config.scheme, "JustAScheme")
        XCTAssertNil(config.project)
        XCTAssertNil(config.workspace)
    }

    func testLoadEmptyFile() throws {
        let path = tempDir + "/nimbus.yml"
        try "".write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: tempDir)
        XCTAssertEqual(config, NimbusConfig.empty)
    }

    func testFindConfigFileWalksUp() throws {
        let subdir = tempDir + "/some/nested/dir"
        try FileManager.default.createDirectory(atPath: subdir, withIntermediateDirectories: true)

        let yaml = "scheme: Found\n"
        try yaml.write(toFile: tempDir + "/nimbus.yml", atomically: true, encoding: .utf8)

        let found = ConfigLoader.findConfigFile(from: subdir)
        XCTAssertEqual(found, tempDir + "/nimbus.yml")
    }

    func testFindConfigFileReturnsNilAtRoot() {
        let found = ConfigLoader.findConfigFile(from: "/tmp/nonexistent-\(UUID().uuidString)")
        XCTAssertNil(found)
    }

    // MARK: - Global Config Tests

    func testLoadGlobalFromCustomPath() throws {
        let globalDir = tempDir + "/.config/nimbus"
        try FileManager.default.createDirectory(atPath: globalDir, withIntermediateDirectories: true)

        let yaml = """
        device: "iPhone 16"
        configuration: Release
        xcbeautify: false
        """
        try yaml.write(toFile: globalDir + "/config.yml", atomically: true, encoding: .utf8)

        let config = try ConfigLoader.loadFile(at: globalDir + "/config.yml")

        XCTAssertEqual(config.device, "iPhone 16")
        XCTAssertEqual(config.configuration, "Release")
        XCTAssertEqual(config.xcbeautify, false)
        XCTAssertNil(config.scheme)
    }

    func testGlobalConfigPathIsWellFormed() {
        XCTAssertTrue(ConfigLoader.globalConfigPath.hasSuffix("/.config/nimbus/config.yml"))
        XCTAssertTrue(ConfigLoader.globalConfigPath.hasPrefix("/"))
    }

    func testGlobalAndProjectMergePrecedence() throws {
        // Simulate global config
        let globalYaml = """
        device: "iPhone 16"
        os: "18.0"
        configuration: Release
        xcbeautify: true
        """
        let globalPath = tempDir + "/global-config.yml"
        try globalYaml.write(toFile: globalPath, atomically: true, encoding: .utf8)
        let globalConfig = try ConfigLoader.loadFile(at: globalPath)

        // Simulate project config (overrides device and adds scheme)
        let projectYaml = """
        scheme: MyApp
        device: "iPhone 17"
        """
        let projectPath = tempDir + "/nimbus.yml"
        try projectYaml.write(toFile: projectPath, atomically: true, encoding: .utf8)
        let projectConfig = try ConfigLoader.loadFile(at: projectPath)

        // Merge: project wins over global
        let merged = globalConfig.merging(with: projectConfig)

        XCTAssertEqual(merged.scheme, "MyApp", "Project scheme should be used")
        XCTAssertEqual(merged.device, "iPhone 17", "Project device should override global")
        XCTAssertEqual(merged.os, "18.0", "Global os should be kept when project doesn't set it")
        XCTAssertEqual(merged.configuration, "Release", "Global configuration should be kept")
        XCTAssertEqual(merged.xcbeautify, true, "Global xcbeautify should be kept")
    }

    func testFullThreeLayerMerge() throws {
        // Global: sets defaults
        let globalYaml = """
        device: "iPhone 16"
        os: "18.0"
        configuration: Release
        xcbeautify: true
        """
        let globalPath = tempDir + "/global-config.yml"
        try globalYaml.write(toFile: globalPath, atomically: true, encoding: .utf8)
        let globalConfig = try ConfigLoader.loadFile(at: globalPath)

        // Project: overrides some global values
        let projectYaml = """
        scheme: MyApp
        device: "iPhone 17"
        configuration: Debug
        """
        let projectPath = tempDir + "/nimbus.yml"
        try projectYaml.write(toFile: projectPath, atomically: true, encoding: .utf8)
        let projectConfig = try ConfigLoader.loadFile(at: projectPath)

        // CLI: overrides everything it sets
        let cliConfig = NimbusConfig(
            project: nil,
            workspace: nil,
            scheme: nil,
            device: "iPad Air",
            os: nil,
            configuration: nil,
            xcbeautify: nil
        )

        let merged = globalConfig.merging(with: projectConfig).merging(with: cliConfig)

        XCTAssertEqual(merged.scheme, "MyApp", "Project scheme preserved (CLI didn't set it)")
        XCTAssertEqual(merged.device, "iPad Air", "CLI device wins over project and global")
        XCTAssertEqual(merged.os, "18.0", "Global os preserved (neither project nor CLI set it)")
        XCTAssertEqual(merged.configuration, "Debug", "Project config wins over global")
        XCTAssertEqual(merged.xcbeautify, true, "Global xcbeautify preserved")
    }
}
