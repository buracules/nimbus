import CryptoKit
import Foundation

/// What "this project" means, in one place.
///
/// Every per-project thing nimbus remembers is filed under this root, and the
/// project file it hands xcodebuild comes from the same answer. If two callers
/// derived it separately they could disagree about which directory is the
/// project, so there is exactly one walk and it lives here, next to
/// `ConfigLoader`, which already owns "walk up and find this project's config".
///
/// Deliberately *not* the git common directory: two worktrees built side by side
/// want two simulators, and the global-config design already excludes
/// project-specific fields so each worktree detects its own. Per-directory keys
/// are consistent with that.
enum ProjectIdentity {
    /// The directory that identifies the project containing `directory`.
    ///
    /// **Nearest wins.** The walk goes up one level at a time and stops at the
    /// first directory holding *either* a `nimbus.yml` or an
    /// `.xcworkspace`/`.xcodeproj`. It does not find every `nimbus.yml` first
    /// and only then look for project files.
    ///
    /// That matters when the two markers sit at different depths. A monorepo
    /// with a shared `nimbus.yml` at the top and two apps below it gets two
    /// project roots, one per app, and therefore two pinned simulators —
    /// which is the same reasoning that gives two git worktrees two roots.
    /// Config discovery is a separate question and keeps its own answer: the
    /// shared `nimbus.yml` above still loads and still applies. "Which
    /// directory is this project" and "which config applies here" are allowed
    /// to differ.
    ///
    /// Falls back to `directory` when the walk reaches the filesystem root
    /// without finding a marker. There is no `.git` stop condition — a project
    /// need not be in git, and stopping at a repo boundary would give this walk
    /// a bound that `ConfigLoader.findConfigFile` does not have.
    static func projectRoot(from directory: String = FileManager.default.currentDirectoryPath) -> String {
        // Resolved before the walk, not after: `/tmp` and `/private/tmp` name
        // one directory, symlinked project directories are common, and
        // resolving first means every level of the walk — and the answer — is
        // already canonical. Without this the same project gets two keys
        // depending on how the user got there.
        let start = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path

        var dir = start
        while true {
            if marksProjectRoot(dir) { return dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        return start
    }

    /// The project or workspace to build, as an absolute path.
    ///
    /// Absolute, and taken from the project root rather than the current
    /// directory, so `nimbus build` works from anywhere inside a project instead
    /// of only from its root. `xcodebuild -workspace` accepts a path, and a bare
    /// file name only resolves when the caller happens to be standing in the
    /// right directory.
    ///
    /// Derived from `projectRoot` on purpose: the file handed to xcodebuild is
    /// by construction the one in the directory that identifies the project, so
    /// the two cannot drift apart.
    static func projectFile(
        from directory: String = FileManager.default.currentDirectoryPath
    ) -> (flag: String, value: String)? {
        let root = projectRoot(from: directory)
        guard let detected = ProjectDetector.detectProjectFile(in: root) else { return nil }
        return (flag: detected.flag, value: (root as NSString).appendingPathComponent(detected.value))
    }

    /// The file name a project's remembered state is stored under.
    ///
    /// A hash rather than the path itself: paths contain `/`, spaces and
    /// non-ASCII, and are longer than a file name may be.
    static func key(for projectRoot: String) -> String {
        SHA256.hash(data: Data(projectRoot.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Whether this single directory is the top of a project.
    ///
    /// Both markers are checked at the same level, which is what makes
    /// nearest-wins a property of the walk rather than of the order two separate
    /// searches happen to run in.
    static func marksProjectRoot(_ directory: String) -> Bool {
        let config = (directory as NSString).appendingPathComponent(ConfigLoader.fileName)
        if FileManager.default.fileExists(atPath: config) { return true }
        return ProjectDetector.detectProjectFile(in: directory) != nil
    }
}
