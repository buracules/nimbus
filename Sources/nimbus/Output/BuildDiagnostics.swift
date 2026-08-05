import Foundation

/// Collects the lines of an xcodebuild run that explain a failure.
///
/// A caller that gets `{"ok": false, "code": "build_failed"}` and nothing else
/// knows less than it did before. It needs the reason, and the reason is in
/// xcodebuild's output — which under `--json` is the one place it cannot look.
/// So the lines that matter are picked out as they stream past and travel in
/// the envelope.
///
/// This does not parse diagnostics into structure. clang, swiftc and xcodebuild
/// all word errors as `<where>: error: <what>`, and test failures as
/// `Test Case ... failed`; matching those two markers is the whole heuristic.
/// Anything more would be a diagnostics parser, which is a different feature.
struct BuildDiagnostics {
    /// A failed build can emit thousands of error lines. The first handful are
    /// almost always the cause and the rest are fallout, and an envelope is not
    /// a log file.
    static let limit = 50

    private(set) var lines: [String] = []
    private var seen: Set<String> = []

    /// Keep this line if it explains something.
    mutating func consider(_ line: String) {
        guard lines.count < Self.limit else { return }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard Self.isDiagnostic(trimmed) else { return }
        guard seen.insert(trimmed).inserted else { return }
        lines.append(trimmed)
    }

    /// Whether a line reports a problem rather than progress.
    static func isDiagnostic(_ line: String) -> Bool {
        if line.contains("error:") { return true }
        if line.hasPrefix("Test Case"), line.contains("failed") { return true }
        return false
    }
}
