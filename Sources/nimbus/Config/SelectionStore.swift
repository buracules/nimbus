import Foundation

/// The simulator a user pinned to a project with `nimbus use`.
///
/// `device` and `os` are named exactly as `NimbusConfig` names them, because a
/// selection is merged into a config rather than translated into one. Two names
/// for one fact is two things to keep true.
///
/// The name is stored, never the UDID. A stored name is an *input to* device
/// resolution; a stored UDID is a *result of* it, and persisting a result would
/// create a second resolution path that bypasses `DeviceResolver` — its
/// fallback, its `matchedRequest` reporting, its suggestions — and would need
/// its own policy for a UDID that no longer exists. Accepted limitation: two
/// simulators with the same name on the same runtime are indistinguishable here.
struct StoredSelection: Codable, Equatable {
    /// Bumped when the meaning of a field changes. An unknown value means the
    /// file is treated as absent, never guessed at.
    static let currentVersion = 1

    var version: Int
    /// Self-describing, so nothing ever has to reverse the file-name hash.
    var projectRoot: String
    var device: String
    var os: String?
    /// Authoritative for ordering. Deliberately not the file's mtime, which
    /// backup and sync tools rewrite.
    var updatedAt: Date

    init(projectRoot: String, device: String, os: String? = nil, updatedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.projectRoot = projectRoot
        self.device = device
        self.os = os
        self.updatedAt = updatedAt
    }
}

/// Reads and writes the per-project simulator selection.
///
/// **The file is private to nimbus.** No other program reads or writes it; the
/// menu bar app and the Alfred workflow call `nimbus use --json` and
/// `nimbus projects --json` instead. That is what keeps the layout, the key
/// derivation, the atomicity and the staleness policy revisable in one commit
/// rather than frozen across three implementations that cannot be deployed
/// together. Document the commands, not this.
///
/// One file per project, not one keyed file: writes for different projects touch
/// different inodes, so there is no shared resource to arbitrate and no stale
/// lock to recover from on the hot path of a one-process-per-invocation CLI.
///
/// Like `DeviceIndex.listAvailableDevices`, reading returns "nothing" rather
/// than failing. A missing, unreadable, undecodable or future-versioned file
/// falls through to the next config layer with a note. There is no TTL: a
/// selection naming a device that no longer exists is not stale state, it is a
/// request `DeviceResolver` misses on and warns about.
enum SelectionStore {
    /// Machine-local state, deliberately not `~/.config/nimbus/`. `.config` is
    /// where the user writes and nimbus reads, and it is commonly symlinked into
    /// a dotfiles repo — machine-local state there would land in version control.
    static var defaultDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/state/nimbus/projects"
    }

    /// What a read produced, and why it produced nothing when there was a file.
    struct LoadResult {
        let selection: StoredSelection?
        /// A line worth showing under `--verbose`. Nil when there was simply
        /// nothing stored.
        let note: String?
    }

    static func path(forProjectRoot root: String, in directory: String = defaultDirectory) -> String {
        (directory as NSString).appendingPathComponent("\(ProjectIdentity.key(for: root)).json")
    }

    // MARK: - Read

    static func load(projectRoot: String, directory: String = defaultDirectory) -> LoadResult {
        let file = path(forProjectRoot: projectRoot, in: directory)
        guard FileManager.default.fileExists(atPath: file) else {
            return LoadResult(selection: nil, note: nil)
        }
        guard let data = FileManager.default.contents(atPath: file) else {
            return LoadResult(selection: nil, note: "could not read \(file); ignoring it")
        }
        switch decode(data) {
        case .success(let selection):
            return LoadResult(selection: selection, note: nil)
        case .failure(let reason):
            return LoadResult(selection: nil, note: "\(file): \(reason); ignoring it")
        }
    }

    /// Every project that still exists on disk and has a stored selection,
    /// newest first.
    ///
    /// This is the whole recents mechanism. Nothing appends to a list — the list
    /// is derived from the files `use` wrote, so it needs no owner for removal
    /// and no lock, and every entry in it was created by a deliberate act.
    static func recents(directory: String = defaultDirectory) -> [StoredSelection] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        return names
            // In-flight writes land on `.tmp-<pid>`, so this also skips a
            // selection that is halfway to disk in another process.
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> StoredSelection? in
                let file = (directory as NSString).appendingPathComponent(name)
                guard let data = fm.contents(atPath: file) else { return nil }
                guard case .success(let selection) = decode(data) else { return nil }
                return selection
            }
            .filter { fm.fileExists(atPath: $0.projectRoot) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Write

    /// Persist a selection, replacing whatever was there.
    ///
    /// Encode, write a sibling temp file, `rename()`. `rename` is atomic on
    /// APFS, so a concurrent reader sees the whole previous file or the whole
    /// new one and never a half-written one. The temp name carries the pid
    /// because nimbus writes once per process invocation, so that is enough to
    /// keep two concurrent `nimbus use` runs off each other's temp file.
    static func save(_ selection: StoredSelection, directory: String = defaultDirectory) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let destination = path(forProjectRoot: selection.projectRoot, in: directory)
        let temporary = "\(destination).tmp-\(ProcessInfo.processInfo.processIdentifier)"

        do {
            let data = try encoder.encode(selection)
            try data.write(to: URL(fileURLWithPath: temporary))
            guard rename(temporary, destination) == 0 else {
                throw NimbusFailure(
                    .commandFailed,
                    "Could not save the simulator selection to \(destination): "
                        + String(cString: strerror(errno))
                )
            }
        } catch {
            // A temp file left behind would never be read (it is not `.json`)
            // but it would never be cleaned up either.
            try? FileManager.default.removeItem(atPath: temporary)
            throw error
        }
    }

    /// Forget a project's selection. Returns whether there was one to forget.
    @discardableResult
    static func clear(projectRoot: String, directory: String = defaultDirectory) throws -> Bool {
        let file = path(forProjectRoot: projectRoot, in: directory)
        guard FileManager.default.fileExists(atPath: file) else { return false }
        try FileManager.default.removeItem(atPath: file)
        return true
    }

    // MARK: - Coding

    /// JSON, not YAML: this file is machine-written and machine-read, `Codable`
    /// gives it for free, and YAML would signal "hand-edit me" — the wrong
    /// signal for a file the tool owns.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private enum Decoded {
        case success(StoredSelection)
        case failure(String)
    }

    /// Version is checked before the rest is decoded, so a future layout that
    /// drops or renames a field is reported as "a different version" rather than
    /// as corruption.
    private struct VersionProbe: Decodable {
        let version: Int
    }

    private static func decode(_ data: Data) -> Decoded {
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            return .failure("not a readable simulator selection")
        }
        guard probe.version == StoredSelection.currentVersion else {
            return .failure("written by a different version of nimbus (version \(probe.version))")
        }
        guard let selection = try? decoder.decode(StoredSelection.self, from: data) else {
            return .failure("incomplete simulator selection")
        }
        return .success(selection)
    }
}
