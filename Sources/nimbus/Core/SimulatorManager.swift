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

    /// List simulator devices, grouped by runtime.
    ///
    /// - Parameter includeUnavailable: when true, devices simctl reports as
    ///   unavailable (missing runtime, unsupported pairing) are kept.
    static func listDevices(includeUnavailable: Bool = false) throws -> [(runtime: String, devices: [Device])] {
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
            .map { entry in
                let devices = includeUnavailable ? entry.value : entry.value.filter { $0.isAvailable }
                return (runtime: entry.key, devices: devices)
            }
            .filter { !$0.devices.isEmpty }
    }

    // MARK: - Runtime Identifiers

    /// Extract the version from a runtime identifier.
    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-2` -> `"26.2"`.
    /// Returns nil when the identifier carries no numeric version.
    static func runtimeVersion(from identifier: String) -> String? {
        guard let lastComponent = identifier.split(separator: ".").last else { return nil }
        var parts = lastComponent.split(separator: "-").map(String.init)
        // Drop the leading platform word ("iOS", "watchOS", ...) if present.
        if let first = parts.first, !isNumeric(first) {
            parts.removeFirst()
        }
        let numeric = parts.prefix { isNumeric($0) }
        guard !numeric.isEmpty else { return nil }
        return numeric.joined(separator: ".")
    }

    /// Extract the platform word from a runtime identifier.
    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-2` -> `"iOS"`.
    static func runtimePlatform(from identifier: String) -> String? {
        guard let lastComponent = identifier.split(separator: ".").last,
              let first = lastComponent.split(separator: "-").first,
              !isNumeric(String(first)) else { return nil }
        return String(first)
    }

    /// Human-readable runtime name: `...SimRuntime.iOS-26-2` -> `"iOS 26.2"`.
    static func runtimeDisplayName(_ identifier: String) -> String {
        guard let version = runtimeVersion(from: identifier) else {
            guard let last = identifier.split(separator: ".").last else { return identifier }
            return last.replacingOccurrences(of: "-", with: " ")
        }
        guard let platform = runtimePlatform(from: identifier) else { return version }
        return "\(platform) \(version)"
    }

    /// Whether a requested OS version identifies the given runtime.
    ///
    /// Comparison is by version *component*, not substring: the requested
    /// components must be a prefix of the runtime's, so `26` matches 26.2 and
    /// `26.2` matches 26.2, but `6.2` does not match 26.2.
    static func runtimeMatches(_ identifier: String, os: String) -> Bool {
        guard let version = runtimeVersion(from: identifier) else { return false }
        let requested = os
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ".")
            .map(String.init)
        guard !requested.isEmpty else { return false }

        let actual = version.split(separator: ".").map(String.init)
        guard requested.count <= actual.count else { return false }

        for (requestedPart, actualPart) in zip(requested, actual) {
            guard let requestedValue = Int(requestedPart),
                  let actualValue = Int(actualPart),
                  requestedValue == actualValue else {
                return false
            }
        }
        return true
    }

    private static func isNumeric(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy { $0.isNumber }
    }

    // MARK: - Device Lookup

    /// Find a simulator matching the given name and optional OS version.
    static func findDevice(name: String, os: String? = nil) throws -> (device: Device, runtime: String)? {
        let groups = try listDevices()
        for group in groups {
            if let os = os, !runtimeMatches(group.runtime, os: os) {
                continue
            }
            if let device = group.devices.first(where: { $0.name == name }) {
                return (device, group.runtime)
            }
        }
        return nil
    }

    /// Find a device with intelligent fallback when exact match isn't found.
    ///
    /// Priority order:
    /// 1. Exact name + OS match (if both specified)
    /// 2. Any booted device matching OS (if OS specified)
    /// 3. Any booted device
    /// 4. First available device matching OS (if OS specified)
    /// 5. First available device
    ///
    /// - Parameters:
    ///   - name: Optional device name to search for
    ///   - os: Optional OS version to filter by
    /// - Returns: A tuple of (device, runtime) or nil if no devices exist
    static func findDeviceWithFallback(name: String?, os: String?) throws -> (device: Device, runtime: String)? {
        let groups = try listDevices()

        // No devices available at all
        if groups.isEmpty {
            return nil
        }

        // Try exact match first if name provided
        if let name = name, let match = try findDevice(name: name, os: os) {
            return match
        }

        // Try booted device matching OS
        if let os = os {
            for group in groups where runtimeMatches(group.runtime, os: os) {
                if let device = group.devices.first(where: { $0.isBooted }) {
                    return (device, group.runtime)
                }
            }
        }

        // Try any booted device
        for group in groups {
            if let device = group.devices.first(where: { $0.isBooted }) {
                return (device, group.runtime)
            }
        }

        // Try first available device matching OS
        if let os = os {
            for group in groups where runtimeMatches(group.runtime, os: os) {
                if let device = group.devices.first {
                    return (device, group.runtime)
                }
            }
        }

        // Fall back to first available device
        if let group = groups.first, let device = group.devices.first {
            return (device, group.runtime)
        }

        return nil
    }

    /// Suggest device names similar to the given query using fuzzy matching.
    ///
    /// - Parameters:
    ///   - query: The device name query that failed to match
    ///   - os: Optional OS version to filter devices by
    /// - Returns: Array of suggested device names (up to 3)
    static func suggestDevices(for query: String, os: String? = nil) throws -> [String] {
        let groups = try listDevices()

        // Filter by OS if provided
        let filteredGroups = groups.filter { group in
            guard let os = os else { return true }
            return runtimeMatches(group.runtime, os: os)
        }

        // Extract all device names
        let allDeviceNames = filteredGroups.flatMap { $0.devices.map { $0.name } }

        // Use FuzzyMatcher to find closest matches
        return FuzzyMatcher.findClosestMatches(target: query, candidates: allDeviceNames, maxResults: 3)
    }

    // MARK: - Simulator Control

    /// Boot a simulator if it's not already booted, and block until it has
    /// finished booting.
    static func boot(udid: String) throws {
        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "boot", udid]
        )
        // exit code 149 means already booted — that's fine
        if !result.succeeded && result.exitCode != 149 {
            throw NimbusError.commandFailed("simctl boot", result.stderr)
        }
        try waitForBoot(udid: udid)
    }

    /// Block until the simulator has finished booting.
    ///
    /// `simctl boot` returns as soon as the boot is under way, so anything that
    /// follows it (install, launch, log stream) can race the boot. `bootstatus`
    /// waits for the real terminal state instead of guessing with a sleep.
    ///
    /// Note: `boot(udid:)` must run first — `bootstatus -b` on its own will
    /// boot the device but does not leave it booted after it exits.
    static func waitForBoot(udid: String) throws {
        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "bootstatus", udid, "-b"]
        )
        guard result.succeeded else {
            throw NimbusError.commandFailed("simctl bootstatus", result.stderr)
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
    /// Returns the most recently modified app bundle matching the scheme name.
    static func findAppBundle(scheme: String, configuration: String = "Debug") -> String? {
        let derivedData = ("~/Library/Developer/Xcode/DerivedData" as NSString)
            .expandingTildeInPath

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: derivedData) else { return nil }

        // Find directories matching the scheme name
        let candidates = contents.filter { $0.contains(scheme) }

        var foundApps: [(path: String, modificationDate: Date)] = []

        for candidate in candidates {
            let buildDir = "\(derivedData)/\(candidate)/Build/Products/\(configuration)-iphonesimulator"
            guard let products = try? fm.contentsOfDirectory(atPath: buildDir) else { continue }
            if let app = products.first(where: { $0.hasSuffix(".app") }) {
                let appPath = "\(buildDir)/\(app)"
                // Get modification date of the app bundle
                if let attrs = try? fm.attributesOfItem(atPath: appPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    foundApps.append((path: appPath, modificationDate: modDate))
                }
            }
        }

        // Return the most recently modified app
        return foundApps.sorted { $0.modificationDate > $1.modificationDate }.first?.path
    }

    /// Extract bundle identifier from an app's Info.plist.
    static func bundleIdentifier(appPath: String) -> String? {
        infoPlistString(appPath: appPath, key: "CFBundleIdentifier")
    }

    /// Extract the executable name from an app's Info.plist.
    ///
    /// This is what shows up at the end of the process image path on a
    /// simulator (`.../MyApp.app/MyApp`), which the bundle identifier never does.
    static func executableName(appPath: String) -> String? {
        infoPlistString(appPath: appPath, key: "CFBundleExecutable")
    }

    private static func infoPlistString(appPath: String, key: String) -> String? {
        let plistPath = "\(appPath)/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
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
