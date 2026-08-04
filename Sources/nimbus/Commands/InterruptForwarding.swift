import Foundation

/// Maps Ctrl+C onto a running operation instead of onto nimbus.
///
/// The default SIGINT action kills nimbus. For anything that has to be *asked*
/// to stop — a recording that only writes its file when interrupted — that
/// means nimbus dies before it can finalize or report anything. Ignoring the
/// default action and forwarding to the operation lets the child finish and
/// lets us print where the result went.
///
/// This is the CLI's half of the cancellation contract: core hands back
/// something stoppable, and each caller maps its own stop gesture onto it. A
/// GUI would map a button here instead.
enum InterruptForwarding {
    /// Run `body` with SIGINT forwarded to `stop`.
    ///
    /// The child is in nimbus's process group, so a terminal Ctrl+C reaches it
    /// directly as well; the forwarded signal is a second one. That is safe for
    /// `simctl recordVideo` — verified: two interrupts 10 ms apart still
    /// produce a valid movie and exit 0.
    static func whileForwarding<T>(to stop: @escaping () -> Void, _ body: () throws -> T) rethrows -> T {
        let previous = signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler(handler: stop)
        source.resume()

        defer {
            source.cancel()
            signal(SIGINT, previous)
        }

        return try body()
    }
}
