import ArgumentParser
import Foundation

/// Runs a command body once and reports its outcome in whichever mode was asked
/// for.
///
/// Every command has the same two endings: it produced a result, or it failed
/// with a reason. Putting both endings here is what keeps `--json` honest — a
/// command cannot narrate a success it did not encode, and it cannot report a
/// failure to a human that it hides from a caller, because it does not report
/// anything itself. It returns a payload or throws a `NimbusFailure`.
enum CommandRunner {
    static func run<Payload: Encodable>(
        _ command: String,
        json: Bool,
        body: () throws -> Payload
    ) throws {
        // Set before the body runs, so every subprocess and stream queue it
        // starts already sees the final value.
        Console.setMachineReadable(json)
        defer { Console.setMachineReadable(false) }

        do {
            let payload = try body()
            if json {
                try CommandOutput.emitSuccess(command: command, data: payload)
            }
        } catch let exit as ExitCode {
            // A body that exits with a code has already said why. Nothing here
            // can add to it, so pass it through unchanged.
            throw exit
        } catch {
            let failure = NimbusFailure(from: error)
            if json {
                try CommandOutput.emitFailure(command: command, failure: failure)
            } else {
                // Diagnostics are deliberately not repeated here: in human mode
                // the formatter already streamed those lines as they arrived.
                Console.error(failure.message)
            }
            throw ExitCode.failure
        }
    }
}
