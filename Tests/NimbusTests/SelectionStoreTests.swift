import XCTest
@testable import nimbus

/// The store persists across restarts and is written by concurrent processes,
/// so a happy-path round trip is not enough evidence. What is checked here is
/// what production punishes: that a damaged file never fails a command, and that
/// a reader cannot observe a half-written one.
final class SelectionStoreTests: XCTestCase {
    private var stateDir: String!
    private var projectDir: String!

    override func setUp() {
        super.setUp()
        let base = NSTemporaryDirectory() + "nimbus-store-\(UUID().uuidString)"
        stateDir = base + "/state"
        projectDir = base + "/project"
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        let base = (stateDir as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: base)
        super.tearDown()
    }

    private func writeRaw(_ contents: String, forProjectRoot root: String) throws {
        let path = SelectionStore.path(forProjectRoot: root, in: stateDir)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Round trip

    func testSaveThenLoadReturnsTheSelection() throws {
        let selection = StoredSelection(projectRoot: projectDir, device: "iPhone 17 Pro", os: "26.2")
        try SelectionStore.save(selection, directory: stateDir)

        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir)
        XCTAssertNil(loaded.note)
        XCTAssertEqual(loaded.selection?.device, "iPhone 17 Pro")
        XCTAssertEqual(loaded.selection?.os, "26.2")
        XCTAssertEqual(loaded.selection?.projectRoot, projectDir)
        XCTAssertEqual(loaded.selection?.version, StoredSelection.currentVersion)
    }

    func testOSIsOmittedWhenUnset() throws {
        try SelectionStore.save(
            StoredSelection(projectRoot: projectDir, device: "iPhone 17"),
            directory: stateDir
        )

        let raw = try String(
            contentsOfFile: SelectionStore.path(forProjectRoot: projectDir, in: stateDir),
            encoding: .utf8
        )
        XCTAssertFalse(raw.contains("\"os\""))
        XCTAssertNil(SelectionStore.load(projectRoot: projectDir, directory: stateDir).selection?.os)
    }

    func testSavingTwiceReplacesRatherThanAppends() throws {
        try SelectionStore.save(StoredSelection(projectRoot: projectDir, device: "iPhone 16"), directory: stateDir)
        try SelectionStore.save(StoredSelection(projectRoot: projectDir, device: "iPhone 17"), directory: stateDir)

        XCTAssertEqual(
            SelectionStore.load(projectRoot: projectDir, directory: stateDir).selection?.device,
            "iPhone 17"
        )
        let files = try FileManager.default.contentsOfDirectory(atPath: stateDir)
        XCTAssertEqual(files.count, 1, "one project must be one file: \(files)")
    }

    func testTheStoredNameIsWhatWasAskedForAndNoUDIDIsKept() throws {
        try SelectionStore.save(
            StoredSelection(projectRoot: projectDir, device: "iPhone 17 Pro", os: "26.2"),
            directory: stateDir
        )
        let raw = try String(
            contentsOfFile: SelectionStore.path(forProjectRoot: projectDir, in: stateDir),
            encoding: .utf8
        )
        XCTAssertFalse(raw.lowercased().contains("udid"), "a UDID is a result of resolution, not an input to it")
        XCTAssertTrue(raw.contains("\"device\""))
        XCTAssertTrue(raw.contains("\"projectRoot\""), "the file must be self-describing")
    }

    // MARK: - Damaged and foreign files fall through

    func testMissingFileIsNotAnError() {
        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir)
        XCTAssertNil(loaded.selection)
        XCTAssertNil(loaded.note, "nothing stored is not worth a note")
    }

    func testMissingDirectoryIsNotAnError() {
        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir + "/never-created")
        XCTAssertNil(loaded.selection)
        XCTAssertNil(loaded.note)
    }

    func testGarbageFallsThroughWithANote() throws {
        try writeRaw("this is not json {{{", forProjectRoot: projectDir)

        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir)
        XCTAssertNil(loaded.selection)
        XCTAssertNotNil(loaded.note, "an ignored file has to be explainable under --verbose")
    }

    func testTruncatedFileFallsThroughWithANote() throws {
        try writeRaw(#"{"version": 1, "projectRoot": "/x""#, forProjectRoot: projectDir)

        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir)
        XCTAssertNil(loaded.selection)
        XCTAssertNotNil(loaded.note)
    }

    func testUnknownVersionIsTreatedAsAbsentRatherThanGuessedAt() throws {
        try writeRaw(
            #"{"version": 99, "projectRoot": "/x", "device": "iPhone 17", "updatedAt": "2026-08-05T09:14:22Z"}"#,
            forProjectRoot: projectDir
        )

        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir)
        XCTAssertNil(loaded.selection)
        XCTAssertEqual(loaded.note?.contains("version 99"), true)
    }

    func testAValidLookingFileMissingARequiredFieldFallsThrough() throws {
        try writeRaw(#"{"version": 1, "projectRoot": "/x"}"#, forProjectRoot: projectDir)

        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir)
        XCTAssertNil(loaded.selection)
        XCTAssertNotNil(loaded.note)
    }

    // MARK: - Clear

    func testClearRemovesTheFileAndReportsWhetherThereWasOne() throws {
        try SelectionStore.save(StoredSelection(projectRoot: projectDir, device: "iPhone 17"), directory: stateDir)

        XCTAssertTrue(try SelectionStore.clear(projectRoot: projectDir, directory: stateDir))
        XCTAssertNil(SelectionStore.load(projectRoot: projectDir, directory: stateDir).selection)
        XCTAssertFalse(try SelectionStore.clear(projectRoot: projectDir, directory: stateDir))
    }

    // MARK: - Recents

    func testRecentsAreOrderedByUpdatedAtAndNotByFilesystemOrder() throws {
        let roots = try (0..<3).map { index -> String in
            let dir = projectDir + "/p\(index)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            return dir
        }

        // Written oldest-first so filesystem order and intended order disagree.
        try SelectionStore.save(
            StoredSelection(projectRoot: roots[0], device: "A", updatedAt: Date(timeIntervalSince1970: 100)),
            directory: stateDir
        )
        try SelectionStore.save(
            StoredSelection(projectRoot: roots[1], device: "B", updatedAt: Date(timeIntervalSince1970: 300)),
            directory: stateDir
        )
        try SelectionStore.save(
            StoredSelection(projectRoot: roots[2], device: "C", updatedAt: Date(timeIntervalSince1970: 200)),
            directory: stateDir
        )

        XCTAssertEqual(SelectionStore.recents(directory: stateDir).map(\.device), ["B", "C", "A"])
    }

    func testRecentsDropProjectsThatNoLongerExist() throws {
        let gone = projectDir + "/deleted"
        try FileManager.default.createDirectory(atPath: gone, withIntermediateDirectories: true)
        try SelectionStore.save(StoredSelection(projectRoot: gone, device: "Ghost"), directory: stateDir)
        try SelectionStore.save(StoredSelection(projectRoot: projectDir, device: "Real"), directory: stateDir)

        try FileManager.default.removeItem(atPath: gone)

        XCTAssertEqual(SelectionStore.recents(directory: stateDir).map(\.device), ["Real"])
    }

    func testRecentsSkipUnreadableEntriesInsteadOfFailing() throws {
        try SelectionStore.save(StoredSelection(projectRoot: projectDir, device: "Real"), directory: stateDir)
        try "garbage".write(toFile: stateDir + "/deadbeef.json", atomically: true, encoding: .utf8)

        XCTAssertEqual(SelectionStore.recents(directory: stateDir).map(\.device), ["Real"])
    }

    func testRecentsIgnoreInFlightTemporaryFiles() throws {
        try SelectionStore.save(StoredSelection(projectRoot: projectDir, device: "Real"), directory: stateDir)
        // What another process's write looks like between create and rename.
        try "half".write(toFile: stateDir + "/deadbeef.json.tmp-4242", atomically: true, encoding: .utf8)

        XCTAssertEqual(SelectionStore.recents(directory: stateDir).count, 1)
    }

    func testRecentsAreEmptyWhenNothingWasEverPinned() {
        XCTAssertTrue(SelectionStore.recents(directory: stateDir + "/never-created").isEmpty)
    }

    // MARK: - Durability and concurrency

    func testSaveLeavesNoTemporaryFileBehind() throws {
        for index in 0..<20 {
            try SelectionStore.save(
                StoredSelection(projectRoot: projectDir, device: "iPhone \(index)"),
                directory: stateDir
            )
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: stateDir)
            .filter { $0.contains(".tmp-") }
        XCTAssertTrue(leftovers.isEmpty, "temp files would accumulate forever: \(leftovers)")
    }

    func testSelectionSurvivesBeingReadByAFreshDecode() throws {
        // The restart case: nothing in memory, only what is on disk.
        let written = StoredSelection(
            projectRoot: projectDir,
            device: "iPhone 17 Pro",
            os: "26.2",
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        try SelectionStore.save(written, directory: stateDir)

        let loaded = SelectionStore.load(projectRoot: projectDir, directory: stateDir).selection
        XCTAssertEqual(loaded, written, "including updatedAt, which orders the recents list")
    }

    /// The claim that one file per project makes the shared resource disappear.
    /// If it were false, concurrent writes would interleave and some project
    /// would read back another's device.
    func testConcurrentWritesToDifferentProjectsDoNotInterfere() throws {
        let count = 32
        let roots = try (0..<count).map { index -> String in
            let dir = projectDir + "/p\(index)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            return dir
        }

        DispatchQueue.concurrentPerform(iterations: count) { index in
            try? SelectionStore.save(
                StoredSelection(projectRoot: roots[index], device: "Device \(index)"),
                directory: stateDir
            )
        }

        for index in 0..<count {
            XCTAssertEqual(
                SelectionStore.load(projectRoot: roots[index], directory: stateDir).selection?.device,
                "Device \(index)"
            )
        }
        XCTAssertEqual(SelectionStore.recents(directory: stateDir).count, count)
    }

    /// The claim that `rename()` makes a write atomic: a reader sees the whole
    /// previous file or the whole new one, never a partial one. Device names of
    /// varying length are used so a torn write would decode to something that is
    /// neither.
    func testReaderNeverObservesAPartiallyWrittenFile() throws {
        let writes = 300
        let names = (0..<writes).map { "iPhone " + String(repeating: "\($0 % 10)", count: 1 + ($0 % 400)) }
        let expected = Set(names)

        let writer = expectation(description: "writer finished")
        DispatchQueue.global().async {
            for name in names {
                try? SelectionStore.save(
                    StoredSelection(projectRoot: self.projectDir, device: name),
                    directory: self.stateDir
                )
            }
            writer.fulfill()
        }

        var observed = 0
        var torn: [String] = []
        let reader = expectation(description: "reader finished")
        DispatchQueue.global().async {
            for _ in 0..<(writes * 4) {
                let result = SelectionStore.load(projectRoot: self.projectDir, directory: self.stateDir)
                if let note = result.note {
                    torn.append(note)
                }
                if let device = result.selection?.device {
                    observed += 1
                    if !expected.contains(device) {
                        torn.append("unexpected device: \(device)")
                    }
                }
            }
            reader.fulfill()
        }

        wait(for: [writer, reader], timeout: 30)
        XCTAssertTrue(torn.isEmpty, "reader saw a file that was neither the old nor the new one: \(torn.prefix(3))")
        XCTAssertGreaterThan(observed, 0, "the reader has to have actually raced the writer")
    }
}
