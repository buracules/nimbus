import XCTest
@testable import nimbus

/// The core/CLI boundary is a rule about ownership: core decides what happened,
/// callers decide what the user is told. Two things make that rule checkable
/// rather than aspirational, so check them.
final class CoreBoundaryTests: XCTestCase {
    private var coreDirectory: String {
        // Tests/NimbusTests/CoreBoundaryTests.swift -> package root
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Sources/nimbus/Core").path
    }

    private func coreSources() throws -> [(name: String, lines: [String])] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: coreDirectory).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "no core sources found at \(coreDirectory)")

        return try files.map { name in
            let contents = try String(contentsOfFile: coreDirectory + "/" + name, encoding: .utf8)
            // Doc comments talk about printing and about the CLI; only code counts.
            let lines = contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            return (name: name, lines: lines)
        }
    }

    func testCoreDoesNotImportArgumentParser() throws {
        for source in try coreSources() {
            for line in source.lines where line.contains("import ArgumentParser") {
                XCTFail("Core/\(source.name) imports ArgumentParser — core must not know about the CLI")
            }
        }
    }

    func testCoreDoesNotWriteToTheTerminal() throws {
        for source in try coreSources() {
            for line in source.lines {
                if line.contains("Console.") {
                    XCTFail("Core/\(source.name) calls Console — core returns values, callers narrate: \(line.trimmingCharacters(in: .whitespaces))")
                }
                if line.contains("print(") {
                    XCTFail("Core/\(source.name) prints — core returns values, callers narrate: \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
    }
}
