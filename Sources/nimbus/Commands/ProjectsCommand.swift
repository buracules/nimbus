import ArgumentParser
import Foundation

/// The projects that have a pinned simulator, most recently pinned first.
///
/// Required, not convenience: without it a consumer with no working directory
/// would have to enumerate nimbus's private state directory itself, which is
/// exactly what keeping that directory private is meant to prevent.
///
/// The list is derived, never recorded. Nothing appends on every invocation —
/// that would be an invisible disk write inside commands whose names do not
/// suggest one, on the hot path of a tool that fights for milliseconds, against
/// a shared list that would be the one structure here needing a lock, and with
/// no owner for removal. Enumerating what `use` wrote has none of those
/// problems, and every entry in it was created by a deliberate act.
struct ProjectsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "List projects with a pinned simulator, most recent first"
    )

    @Flag(name: .long, help: "Emit a JSON result envelope on stdout instead of human output")
    var json = false

    mutating func run() throws {
        let json = self.json

        try CommandRunner.run("projects", json: json) {
            let payload = ProjectsPayload(
                projects: SelectionStore.recents().map {
                    ProjectsPayload.Entry(
                        projectRoot: $0.projectRoot,
                        device: $0.device,
                        os: $0.os,
                        updatedAt: $0.updatedAt
                    )
                }
            )

            if !Console.isMachineReadable {
                Self.render(payload)
            }
            return payload
        }
    }

    private static func render(_ payload: ProjectsPayload) {
        guard !payload.projects.isEmpty else {
            Console.info("No projects have a pinned simulator yet.")
            Console.detail("  Run 'nimbus use \"iPhone 17 Pro\"' inside one.")
            return
        }

        let formatter = ISO8601DateFormatter()
        for entry in payload.projects {
            Console.detail(Console.colored("\n\(entry.projectRoot)", .bold))
            let os = entry.os.map { " · OS \($0)" } ?? ""
            Console.detail("  \(entry.device)\(os) · \(formatter.string(from: entry.updatedAt))")
        }
        Console.detail()
    }
}
