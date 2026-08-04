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
        let choice = try options.selectBootedDevice()
        let target = path.map(SimPaths.absolute) ?? SimPaths.defaultPath(prefix: "screenshot", extension: type ?? "png")

        let file = try SimulatorControl.screenshot(udid: choice.device.udid, path: target, type: type)
        Console.success("Screenshot saved to \(file.path)")
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
            Console.error("Recording failed (exit \(exitCode))")
            throw ExitCode.failure
        }
        Console.success("Recording saved to \(recording.path)")
    }
}
