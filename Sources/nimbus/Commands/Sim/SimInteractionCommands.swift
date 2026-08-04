import ArgumentParser
import Foundation

struct SimOpenURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openurl",
        abstract: "Open a URL on the simulator"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "The URL to open, including scheme")
    var url: String

    mutating func run() throws {
        let choice = try options.selectBootedDevice()
        try SimulatorControl.openURL(udid: choice.device.udid, url: url)
        Console.success("Opened \(url) on \(choice.device.name)")
    }
}

struct SimPushCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Send a simulated push notification"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "Path to a JSON payload containing an 'aps' key")
    var payload: String

    @Option(name: .customLong("bundle-id"), help: "Target app; optional when the payload names one")
    var bundleID: String?

    mutating func run() throws {
        let payloadPath = SimPaths.absolute(payload)
        guard FileManager.default.fileExists(atPath: payloadPath) else {
            Console.error("Payload not found at \(payloadPath)")
            throw ExitCode.failure
        }

        let choice = try options.selectBootedDevice()
        try SimulatorControl.push(udid: choice.device.udid, bundleID: bundleID, payloadPath: payloadPath)
        Console.success("Push delivered to \(bundleID ?? "the payload's target") on \(choice.device.name)")
    }
}

struct SimPrivacyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "privacy",
        abstract: "Grant, revoke or reset a privacy permission"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "grant, revoke or reset")
    var action: SimulatorControl.PrivacyAction

    @Argument(help: "Service, e.g. photos, contacts, location, microphone, or 'all'")
    var service: String

    @Option(name: .customLong("bundle-id"), help: "Target app; required for grant and revoke")
    var bundleID: String?

    mutating func run() throws {
        // simctl requires a bundle identifier for grant and revoke, and fails
        // late and cryptically without one.
        if action != .reset, bundleID == nil {
            Console.error("--bundle-id is required for \(action.rawValue)")
            throw ExitCode.failure
        }

        let choice = try options.selectBootedDevice()
        try SimulatorControl.privacy(
            udid: choice.device.udid,
            action: action,
            service: service,
            bundleID: bundleID
        )
        Console.success("\(action.rawValue) \(service) on \(choice.device.name)")
    }
}

extension SimulatorControl.PrivacyAction: ExpressibleByArgument {}
