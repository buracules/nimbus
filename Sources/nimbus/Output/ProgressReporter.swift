import Foundation

/// Built-in xcodebuild output formatter that extracts meaningful lines
/// from the verbose xcodebuild output. Used as a fallback when xcbeautify
/// is not installed.
struct ProgressReporter {
    private let verbose: Bool

    init(verbose: Bool = false) {
        self.verbose = verbose
    }

    /// Process a single line of xcodebuild output and return a formatted
    /// version, or nil if the line should be suppressed.
    func format(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { return nil }

        // Errors and warnings always pass through
        if trimmed.contains("error:") {
            return Console.colored("  ✗ \(trimmed)", .red)
        }
        if trimmed.contains("warning:") {
            return Console.colored("  ⚠ \(trimmed)", .yellow)
        }

        // In verbose mode, pass everything through
        if verbose {
            return trimmed
        }

        // Compile steps
        if trimmed.hasPrefix("CompileC ") || trimmed.hasPrefix("CompileSwift ") {
            return extractFilename(from: trimmed).map { "  Compiling \($0)" }
        }
        if trimmed.hasPrefix("CompileSwiftSources") {
            return "  Compiling Swift sources..."
        }

        // Link step
        if trimmed.hasPrefix("Ld ") {
            return extractProduct(from: trimmed).map { "  Linking \($0)" }
        }

        // Code signing
        if trimmed.hasPrefix("CodeSign ") || trimmed.hasPrefix("SigningCert") {
            return "  Signing..."
        }

        // Copy/process resources
        if trimmed.hasPrefix("CpResource ") || trimmed.hasPrefix("CopyPlistFile ") {
            return extractFilename(from: trimmed).map { "  Copying \($0)" }
        }
        if trimmed.hasPrefix("CompileAssetCatalog") {
            return "  Compiling asset catalog..."
        }
        if trimmed.hasPrefix("CompileStoryboard") || trimmed.hasPrefix("CompileXIB") {
            return extractFilename(from: trimmed).map { "  Compiling \($0)" }
        }
        if trimmed.hasPrefix("ProcessInfoPlistFile") {
            return "  Processing Info.plist..."
        }

        // Build phases
        if trimmed.hasPrefix("PhaseScriptExecution") {
            return extractScriptName(from: trimmed).map { "  Running script: \($0)" }
        }

        // Build succeeded/failed
        if trimmed.hasPrefix("** BUILD SUCCEEDED **") {
            return Console.colored("  Build Succeeded", .green)
        }
        if trimmed.hasPrefix("** BUILD FAILED **") {
            return Console.colored("  Build Failed", .red)
        }
        if trimmed.hasPrefix("** TEST SUCCEEDED **") {
            return Console.colored("  Tests Passed", .green)
        }
        if trimmed.hasPrefix("** TEST FAILED **") {
            return Console.colored("  Tests Failed", .red)
        }
        if trimmed.hasPrefix("** CLEAN SUCCEEDED **") {
            return Console.colored("  Clean Succeeded", .green)
        }

        // Test results
        if trimmed.hasPrefix("Test Case") {
            if trimmed.contains("passed") {
                return Console.colored("  ✓ \(trimmed)", .green)
            } else if trimmed.contains("failed") {
                return Console.colored("  ✗ \(trimmed)", .red)
            }
        }

        // Suppress everything else
        return nil
    }

    private func extractFilename(from line: String) -> String? {
        // xcodebuild lines often end with a file path; extract the filename
        let components = line.split(separator: " ")
        if let last = components.last {
            let path = String(last)
            return (path as NSString).lastPathComponent
        }
        return nil
    }

    private func extractProduct(from line: String) -> String? {
        let components = line.split(separator: " ")
        if components.count >= 2 {
            return String(components[1])
        }
        return nil
    }

    private func extractScriptName(from line: String) -> String? {
        // PhaseScriptExecution "Script Name" ...
        guard let openQuote = line.firstIndex(of: "\"") else { return nil }
        let afterOpen = line.index(after: openQuote)
        guard let closeQuote = line[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(line[afterOpen..<closeQuote])
    }
}
