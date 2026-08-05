import XCTest
@testable import nimbus

/// `--json` was shipped once before as a flag that appeared in `--help` and
/// printed ordinary text, and it had to be pulled. Two rules stop that from
/// happening again, and both are checkable from the source rather than from
/// someone remembering.
final class JSONOutputBoundaryTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/nimbus")
    }

    private func swiftFiles(under relativePath: String) throws -> [(name: String, contents: String)] {
        let directory = sourceRoot.appendingPathComponent(relativePath)
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: directory.path) else {
            XCTFail("no sources found at \(directory.path)")
            return []
        }

        var files: [(name: String, contents: String)] = []
        for case let path as String in walker where path.hasSuffix(".swift") {
            let contents = try String(
                contentsOf: directory.appendingPathComponent(path),
                encoding: .utf8
            )
            files.append((name: path, contents: contents))
        }
        XCTAssertFalse(files.isEmpty, "no sources found at \(directory.path)")
        return files
    }

    /// A command that advertises `--json` must go through `CommandRunner`,
    /// which is the only thing that emits an envelope. Advertising the flag
    /// without it is precisely the lie that got the last attempt reverted.
    func testEveryCommandThatAdvertisesJSONEmitsAnEnvelope() throws {
        // These define the flag rather than offering it.
        let optionDefinitions: Set<String> = ["SharedOptions.swift", "DeviceOptions.swift"]
        var checked = 0

        for file in try swiftFiles(under: "Commands") {
            let name = (file.name as NSString).lastPathComponent
            guard !optionDefinitions.contains(name) else { continue }

            let advertisesJSON = file.contents.contains("var options: SharedOptions")
                || file.contents.contains("var options: DeviceOptions")
                || file.contents.contains("var json = false")
            guard advertisesJSON else { continue }

            checked += 1
            XCTAssertTrue(
                file.contents.contains("CommandRunner.run("),
                "Commands/\(file.name) offers --json but never emits an envelope"
            )
        }

        // Guards against the check quietly matching nothing and passing.
        XCTAssertGreaterThanOrEqual(checked, 9, "expected to find every command file that offers --json")
    }

    /// Under `--json`, stdout carries the envelope and nothing else. Console
    /// routes narration to stderr for that reason, so a bare `print` is the one
    /// way decorative output can still leak — every remaining one needs a
    /// reason.
    func testOnlyKnownPlacesWriteDirectlyToStandardOutput() throws {
        let allowed: [String: String] = [
            "Output/Console.swift": "owns the routing",
            "Output/CommandOutput.swift": "writes the envelope itself",
            "Output/DevicePicker.swift": "the interactive menu, which refuses to run under --json",
            "Commands/RunCommand.swift": "the --logs console stream, which refuses --json",
            "Commands/LogsCommand.swift": "the log stream, which refuses --json",
            "Commands/BuildExecutor.swift": "the human formatter, used only when not machine-readable",
        ]

        for directory in ["Commands", "Output", "Core", "Config", "Utilities"] {
            for file in try swiftFiles(under: directory) {
                let key = "\(directory)/\(file.name)"
                guard allowed[key] == nil else { continue }

                let lines = file.contents
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }

                for line in lines where line.contains("print(") {
                    XCTFail(
                        "\(key) writes to stdout directly — use Console, which knows about --json: "
                            + line.trimmingCharacters(in: .whitespaces)
                    )
                }
            }
        }
    }
}
