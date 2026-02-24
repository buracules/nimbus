import Foundation

/// Wraps `xcrun simctl` for simulator management.
enum SimulatorManager {
    struct Device: Codable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
        let availabilityError: String?

        var isBooted: Bool { state == "Booted" }
    }

    struct Runtime: Codable, Hashable {
        let identifier: String
        let name: String
        let version: String
        let isAvailable: Bool
    }

    struct DeviceList: Codable {
        let devices: [String: [Device]]
    }

    // MARK: - Device Listing

    /// List all available simulator devices, grouped by runtime.
    static func listDevices() throws -> [(runtime: String, devices: [Device])] {
        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "--json"]
        )
        guard result.succeeded else {
            throw NimbusError.commandFailed("simctl list devices", result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw NimbusError.parseError("Failed to parse simctl output")
        }

        let decoder = JSONDecoder()
        let deviceList = try decoder.decode(DeviceList.self, from: data)

        return deviceList.devices
            .sorted { $0.key < $1.key }
            .map { (runtime: $0.key, devices: $0.value.filter { $0.isAvailable }) }
            .filter { !$0.devices.isEmpty }
    }

    // MARK: - Device Lookup

    /// Find a simulator matching the given name and optional OS version.
    static func findDevice(name: String, os: String? = nil) throws -> (device: Device, runtime: String)? {
        let groups = try listDevices()
        for group in groups {
            if let os = os,
               !group.runtime.contains(os),
               !group.runtime.contains(os.replacingOccurrences(of: ".", with: "-")) {
                continue
            }
            if let device = group.devices.first(where: { $0.name == name }) {
                return (device, group.runtime)
            }
        }
        return nil
    }

    // MARK: - Simulator Control

    /// Boot a simulator if it's not already booted.
    static func boot(udid: String) throws {
        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "boot", udid]
        )
        // exit code 149 means already booted — that's fine
        if !result.succeeded && result.exitCode != 149 {
            throw NimbusError.commandFailed("simctl boot", result.stderr)
        }
    }

    /// Open Simulator.app.
    static func openSimulatorApp() throws {
        try ProcessRunner.run("/usr/bin/open", arguments: ["-a", "Simulator"])
    }

    /// Install an app bundle on a simulator.
    static func install(udid: String, appPath: String) throws {
        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "install", udid, appPath]
        )
        guard result.succeeded else {
            throw NimbusError.commandFailed("simctl install", result.stderr)
        }
    }

    /// Launch an app on a simulator by bundle identifier.
    static func launch(udid: String, bundleID: String) throws {
        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "launch", udid, bundleID]
        )
        guard result.succeeded else {
            throw NimbusError.commandFailed("simctl launch", result.stderr)
        }
    }

    /// Get the path to the built app in DerivedData.
    static func findAppBundle(scheme: String, configuration: String = "Debug") -> String? {
        let derivedData = ("~/Library/Developer/Xcode/DerivedData" as NSString)
            .expandingTildeInPath

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: derivedData) else { return nil }

        // Find directories matching the scheme name
        let candidates = contents.filter { $0.hasPrefix(scheme) || $0.contains(scheme) }

        for candidate in candidates {
            let buildDir = "\(derivedData)/\(candidate)/Build/Products/\(configuration)-iphonesimulator"
            guard let products = try? fm.contentsOfDirectory(atPath: buildDir) else { continue }
            if let app = products.first(where: { $0.hasSuffix(".app") }) {
                return "\(buildDir)/\(app)"
            }
        }
        return nil
    }

    /// Extract bundle identifier from an app's Info.plist.
    static func bundleIdentifier(appPath: String) -> String? {
        let plistPath = "\(appPath)/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            return nil
        }
        return bundleID
    }
}

// MARK: - Error Types

enum NimbusError: LocalizedError {
    case commandFailed(String, String)
    case parseError(String)
    case configError(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let stderr):
            return "\(command) failed: \(stderr)"
        case .parseError(let message):
            return message
        case .configError(let message):
            return message
        case .notFound(let what):
            return "\(what) not found"
        }
    }
}
