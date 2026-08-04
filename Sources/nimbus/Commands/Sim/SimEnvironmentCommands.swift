import ArgumentParser
import Foundation

struct SimAppearanceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appearance",
        abstract: "Get or set light/dark appearance"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "light or dark; omit to print the current appearance")
    var style: SimulatorControl.Appearance?

    mutating func run() throws {
        let choice = try options.selectBootedDevice()

        guard let style else {
            let current = try SimulatorControl.currentAppearance(udid: choice.device.udid)
            Console.info("Appearance on \(choice.device.name): \(current)")
            return
        }

        try SimulatorControl.setAppearance(udid: choice.device.udid, style: style)
        Console.success("Appearance set to \(style.rawValue) on \(choice.device.name)")
    }
}

struct SimStatusBarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "statusbar",
        abstract: "Override the status bar, or clear the overrides"
    )

    @OptionGroup var options: DeviceOptions

    @Flag(name: .long, help: "Clear all status bar overrides")
    var clear = false

    @Option(name: .long, help: "Time to display, e.g. 9:41")
    var time: String?

    @Option(name: .customLong("battery-level"), help: "Battery percentage, 0-100")
    var batteryLevel: Int?

    @Option(name: .customLong("battery-state"), help: "charging, charged or discharging")
    var batteryState: String?

    @Option(name: .customLong("wifi-bars"), help: "Wi-Fi bars, 0-3")
    var wifiBars: Int?

    @Option(name: .customLong("cellular-bars"), help: "Cellular bars, 0-4")
    var cellularBars: Int?

    @Option(name: .customLong("data-network"), help: "wifi, 5g, lte, 4g, 3g or hide")
    var dataNetwork: String?

    @Option(name: .customLong("operator-name"), help: "Carrier name")
    var operatorName: String?

    mutating func run() throws {
        let overrides = Self.overrideArguments(
            time: time,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            wifiBars: wifiBars,
            cellularBars: cellularBars,
            dataNetwork: dataNetwork,
            operatorName: operatorName
        )

        guard clear || !overrides.isEmpty else {
            Console.error("Nothing to do. Pass --clear or at least one override such as --time 9:41.")
            throw ExitCode.failure
        }

        let choice = try options.selectBootedDevice()

        if clear {
            try SimulatorControl.clearStatusBar(udid: choice.device.udid)
            Console.success("Status bar overrides cleared on \(choice.device.name)")
            return
        }

        try SimulatorControl.overrideStatusBar(udid: choice.device.udid, overrides: overrides)
        Console.success("Status bar updated on \(choice.device.name)")
    }

    /// Translate nimbus's flags into simctl's. Pure, so the mapping is testable.
    static func overrideArguments(
        time: String? = nil,
        batteryLevel: Int? = nil,
        batteryState: String? = nil,
        wifiBars: Int? = nil,
        cellularBars: Int? = nil,
        dataNetwork: String? = nil,
        operatorName: String? = nil
    ) -> [String] {
        var args: [String] = []
        if let time { args += ["--time", time] }
        if let batteryState { args += ["--batteryState", batteryState] }
        if let batteryLevel { args += ["--batteryLevel", String(batteryLevel)] }
        if let dataNetwork { args += ["--dataNetwork", dataNetwork] }
        if let wifiBars { args += ["--wifiBars", String(wifiBars)] }
        if let cellularBars { args += ["--cellularBars", String(cellularBars)] }
        if let operatorName { args += ["--operatorName", operatorName] }
        return args
    }
}

struct SimLocationCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "location",
        abstract: "Set or clear the simulated location"
    )

    @OptionGroup var options: DeviceOptions

    @Argument(help: "Coordinates as lat,lon — e.g. 37.3349,-122.0090")
    var coordinates: String?

    @Flag(name: .long, help: "Clear the simulated location")
    var clear = false

    mutating func run() throws {
        if clear {
            let choice = try options.selectBootedDevice()
            try SimulatorControl.clearLocation(udid: choice.device.udid)
            Console.success("Location cleared on \(choice.device.name)")
            return
        }

        guard let coordinates else {
            Console.error("Pass coordinates as lat,lon — e.g. 37.3349,-122.0090 — or --clear.")
            throw ExitCode.failure
        }
        guard let point = Self.parseCoordinates(coordinates) else {
            Console.error("Could not read '\(coordinates)' as lat,lon.")
            throw ExitCode.failure
        }

        let choice = try options.selectBootedDevice()
        try SimulatorControl.setLocation(
            udid: choice.device.udid,
            latitude: point.latitude,
            longitude: point.longitude
        )
        Console.success("Location set to \(point.latitude),\(point.longitude) on \(choice.device.name)")
    }

    /// Parse `lat,lon`, rejecting anything out of range rather than handing
    /// simctl a coordinate it will refuse.
    static func parseCoordinates(_ value: String) -> (latitude: Double, longitude: Double)? {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        return (latitude, longitude)
    }
}

extension SimulatorControl.Appearance: ExpressibleByArgument {}
