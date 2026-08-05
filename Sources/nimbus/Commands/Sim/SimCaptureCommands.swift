import ArgumentParser
import Foundation

struct SimScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Save a screenshot of the simulator"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "Where to write the image (default: ./nimbus-screenshot-<timestamp>.png)")
    var path: String?

    @Option(name: .long, help: "Image type: png, tiff, bmp, gif or jpeg")
    var type: String?

    mutating func run() throws {
        let options = self.options
        let path = self.path
        let type = self.type

        try CommandRunner.run("sim screenshot", json: options.json) {
            let choice = try options.selectBootedDevice()
            let target = path.map(SimPaths.absolute)
                ?? SimPaths.defaultPath(prefix: "screenshot", extension: type ?? "png")

            let file = try SimulatorControl.screenshot(udid: choice.device.udid, path: target, type: type)
            Console.success("Screenshot saved to \(file.path)")
            return SimCapturePayload(resolution: choice.resolution, file: file)
        }
    }
}

struct SimRecordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record the simulator screen until stopped"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "Where to write the movie (default: ./nimbus-recording-<timestamp>.mov)")
    var path: String?

    @Option(name: .long, help: "Video codec: h264 or hevc")
    var codec: String?

    mutating func run() throws {
        let options = self.options
        let path = self.path
        let codec = self.codec

        try CommandRunner.run("sim record", json: options.json) {
            try Self.perform(options: options, path: path, codec: codec)
        }
    }

    /// Records until interrupted, then reports the movie.
    ///
    /// This is long-running but it is not a stream: nothing goes to stdout
    /// while it runs, so the envelope at the end is safe. `logs` is the
    /// opposite case, and refuses `--json` for exactly that reason.
    private static func perform(
        options: DeviceOptions,
        path: String?,
        codec: String?
    ) throws -> SimCapturePayload {
        let choice = try options.selectBootedDevice()
        let target = path.map(SimPaths.absolute) ?? SimPaths.defaultPath(prefix: "recording", extension: "mov")
        let isVerbose = options.verbose

        let recording = try SimulatorControl.startRecording(
            udid: choice.device.udid,
            path: target,
            codec: codec,
            onOutputLine: { line in
                Console.verbose(line, isVerbose: isVerbose)
            }
        )

        Console.step("Recording \(choice.device.name)...")
        Console.info("Press Ctrl+C to stop and write the movie")

        // The movie only exists if simctl is asked to stop; Ctrl+C must reach
        // the recording rather than killing nimbus before it can report.
        let exitCode = InterruptForwarding.whileForwarding(to: { recording.stop() }) {
            recording.waitUntilFinished()
        }

        guard exitCode == 0 else {
            throw NimbusFailure(
                .commandFailed,
                "Recording failed (exit \(exitCode))",
                exitCode: exitCode
            )
        }
        Console.success("Recording saved to \(recording.path)")
        return SimCapturePayload(
            resolution: choice.resolution,
            file: SimulatorControl.CapturedFile(path: recording.path)
        )
    }
}
