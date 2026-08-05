import Foundation

/// A stable identifier for a failure.
///
/// These strings are the part of the contract callers branch on. A message is
/// for a human to read and may be reworded at any time; a code is not. Add
/// cases freely, rename them never.
enum NimbusErrorCode: String, Encodable {
    /// `xcodebuild build` returned non-zero.
    case buildFailed = "build_failed"
    /// `xcodebuild test` returned non-zero.
    case testFailed = "test_failed"
    /// `xcodebuild clean` returned non-zero.
    case cleanFailed = "clean_failed"
    /// This machine has no simulators to run on.
    case noSimulators = "no_simulators"
    /// The interactive picker was cancelled.
    case noDeviceSelected = "no_device_selected"
    /// No scheme was configured and none could be detected.
    case schemeUnknown = "scheme_unknown"
    /// The built `.app` could not be found on disk.
    case appBundleNotFound = "app_bundle_not_found"
    /// The app's bundle identifier could not be read.
    case bundleIdentifierUnknown = "bundle_identifier_unknown"
    /// Xcode's command line tools are missing.
    case xcodebuildNotFound = "xcodebuild_not_found"
    /// A config file already exists and `--force` was not given.
    case configExists = "config_exists"
    /// The flags or arguments given cannot be acted on.
    case invalidArguments = "invalid_arguments"
    /// A file the command was pointed at does not exist.
    case fileNotFound = "file_not_found"
    /// An underlying tool (usually `simctl`) failed.
    case commandFailed = "command_failed"
    /// A tool's output could not be read.
    case parseError = "parse_error"
    /// A config file could not be loaded.
    case configError = "config_error"
    /// Something nimbus looked for was not there.
    case notFound = "not_found"
    /// `--json` was asked for on a command that streams stdout.
    case unsupportedOutputMode = "unsupported_output_mode"
    /// Anything nimbus did not classify.
    case internalError = "internal_error"
}

/// A failure, in the shape the envelope reports it.
///
/// Command bodies throw this instead of printing an error and throwing
/// `ExitCode.failure`, so that the same failure can be worded for a human or
/// encoded for a caller without the two drifting apart.
struct NimbusFailure: Error {
    let code: NimbusErrorCode
    let message: String
    /// The underlying tool's exit code, when there was one.
    let exitCode: Int32?
    /// Lines the underlying tool emitted that explain the failure.
    let diagnostics: [String]

    init(
        _ code: NimbusErrorCode,
        _ message: String,
        exitCode: Int32? = nil,
        diagnostics: [String] = []
    ) {
        self.code = code
        self.message = message
        self.exitCode = exitCode
        self.diagnostics = diagnostics
    }

    /// Classify anything a command body can throw.
    init(from error: Error) {
        if let failure = error as? NimbusFailure {
            self = failure
            return
        }
        if let nimbusError = error as? NimbusError {
            self.init(
                NimbusErrorCode(nimbusError),
                nimbusError.errorDescription ?? String(describing: nimbusError)
            )
            return
        }
        self.init(.internalError, error.localizedDescription)
    }
}

extension NimbusErrorCode {
    /// Core throws `NimbusError`; the envelope reports codes. This is the one
    /// place the two vocabularies meet.
    init(_ error: NimbusError) {
        switch error {
        case .commandFailed: self = .commandFailed
        case .parseError: self = .parseError
        case .configError: self = .configError
        case .notFound: self = .notFound
        }
    }
}

extension NimbusFailure: Encodable {
    private enum CodingKeys: String, CodingKey {
        case code, message, exitCode, diagnostics
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        if !diagnostics.isEmpty {
            try container.encode(diagnostics, forKey: .diagnostics)
        }
    }
}

/// A payload for a command that succeeds without producing anything to report.
struct EmptyPayload: Encodable {}

/// The `--json` contract: exactly one object on stdout, shaped
/// `{"ok": Bool, "command": String, "data": ...}` on success and
/// `{"ok": false, "command": String, "error": {...}}` on failure.
///
/// The envelope belongs to the CLI. What it carries does not — every payload is
/// composed of the types core already returns, so there is no second model of
/// nimbus's facts to keep in step with the first.
enum CommandOutput {
    private struct Envelope<Payload: Encodable>: Encodable {
        let ok: Bool
        let command: String
        let data: Payload?
        let error: NimbusFailure?
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted keys make the output diffable and reproducible; unescaped
        // slashes keep file paths readable, which is most of what nimbus reports.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func emitSuccess<Payload: Encodable>(command: String, data: Payload) throws {
        try emit(Envelope(ok: true, command: command, data: data, error: nil))
    }

    static func emitFailure(command: String, failure: NimbusFailure) throws {
        try emit(Envelope<EmptyPayload>(ok: false, command: command, data: nil, error: failure))
    }

    /// Render an envelope without printing it. Exists so the shape can be
    /// asserted in tests rather than eyeballed on a terminal.
    static func render<Payload: Encodable>(command: String, data: Payload) throws -> String {
        try string(from: Envelope(ok: true, command: command, data: data, error: nil))
    }

    static func render(command: String, failure: NimbusFailure) throws -> String {
        try string(from: Envelope<EmptyPayload>(ok: false, command: command, data: nil, error: failure))
    }

    private static func emit<Payload: Encodable>(_ envelope: Envelope<Payload>) throws {
        print(try string(from: envelope))
    }

    private static func string<Payload: Encodable>(from envelope: Envelope<Payload>) throws -> String {
        let data = try encoder.encode(envelope)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
