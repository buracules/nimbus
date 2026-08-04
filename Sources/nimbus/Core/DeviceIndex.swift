import Foundation

/// Enumerates simulators by reading CoreSimulator's own files instead of
/// shelling out to `xcrun simctl list devices --json`.
///
/// `simctl list` costs 330-510 ms on this machine because it round-trips
/// through CoreSimulatorService; reading the device plists costs ~6 ms.
/// Device resolution runs on every build/run/test/logs/sim invocation, so that
/// difference is most of the latency budget of a command like `sim screenshot`.
///
/// What this index is exact about, verified device-by-device against
/// `simctl list devices --json`: UDID, name, runtime identifier, and whether
/// the device is usable (its runtime is installed).
///
/// What it is *not* exact about is `state`. CoreSimulator writes the state into
/// `device.plist` only once a transition has completed: racing `simctl boot`
/// against the plist shows the file still reading Shutdown while simctl already
/// reports Booted, and racing `simctl shutdown` shows it still reading Booted
/// for the whole shutdown. State here is a hint that is correct at rest and
/// stale mid-transition — anything that *requires* a booted device must go
/// through `simctl bootstatus`, which is authoritative and blocks.
enum DeviceIndex {
    /// The fields of one `device.plist` that we care about.
    struct Entry: Equatable {
        let udid: String
        let name: String
        let runtime: String
        let state: Int
        let isDeleted: Bool
    }

    // MARK: - Locations

    static var defaultDevicesDirectory: String {
        ("~/Library/Developer/CoreSimulator/Devices" as NSString).expandingTildeInPath
    }

    /// The active developer directory, without paying for an `xcode-select -p`
    /// process: `DEVELOPER_DIR` wins, then the symlink `xcode-select` maintains.
    static func developerDirectory() -> String? {
        if let env = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !env.isEmpty {
            return env
        }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")
    }

    /// Directories that directly contain `.simruntime` bundles.
    ///
    /// Runtimes live in three shapes: installed-in-place under Library, mounted
    /// per-version under `CoreSimulator/Volumes/<build>/...` (how Xcode 16+
    /// stores downloaded runtimes), and cryptex mounts for beta runtimes.
    static func defaultRuntimeDirectories() -> [String] {
        var directories = [
            ("~/Library/Developer/CoreSimulator/Profiles/Runtimes" as NSString).expandingTildeInPath,
            "/Library/Developer/CoreSimulator/Profiles/Runtimes",
        ]
        if let developer = developerDirectory() {
            directories.append(
                "\(developer)/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes"
            )
        }
        let mountSuffix = "Library/Developer/CoreSimulator/Profiles/Runtimes"
        directories += expandMountContainer("/Library/Developer/CoreSimulator/Volumes", suffix: mountSuffix)
        directories += expandMountContainer("/private/var/run/com.apple.security.cryptexd/mnt", suffix: mountSuffix)
        return directories
    }

    /// List one level of `container` and append `suffix` to each child.
    static func expandMountContainer(_ container: String, suffix: String) -> [String] {
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: container) else { return [] }
        return children.sorted().map { "\(container)/\($0)/\(suffix)" }
    }

    // MARK: - Parsing

    /// The CoreSimulator `SimDeviceState` codes, named the way simctl names them.
    static func stateName(_ raw: Int) -> String {
        switch raw {
        case 0: return "Creating"
        case 1: return "Shutdown"
        case 2: return "Booting"
        case 3: return "Booted"
        case 4: return "Shutting Down"
        default: return "Unknown"
        }
    }

    /// Parse one `device.plist`. Returns nil when the payload is not a device
    /// plist we understand — callers treat that as "distrust the whole index".
    static func parseEntry(plistData data: Data) -> Entry? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let udid = plist["UDID"] as? String, !udid.isEmpty,
              let name = plist["name"] as? String, !name.isEmpty,
              let runtime = plist["runtime"] as? String, !runtime.isEmpty,
              let state = plist["state"] as? Int else {
            return nil
        }
        return Entry(
            udid: udid,
            name: name,
            runtime: runtime,
            state: state,
            isDeleted: plist["isDeleted"] as? Bool ?? false
        )
    }

    /// The runtime identifiers installed on this machine, read from the
    /// `CFBundleIdentifier` of every `.simruntime` bundle found.
    static func installedRuntimeIdentifiers(in directories: [String]) -> Set<String> {
        let fm = FileManager.default
        var identifiers: Set<String> = []

        for directory in directories {
            guard let children = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for child in children where child.hasSuffix(".simruntime") {
                let infoPath = "\(directory)/\(child)/Contents/Info.plist"
                guard let data = fm.contents(atPath: infoPath),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let identifier = plist["CFBundleIdentifier"] as? String,
                      !identifier.isEmpty else {
                    continue
                }
                identifiers.insert(identifier)
            }
        }
        return identifiers
    }

    // MARK: - Enumeration

    /// Every device whose runtime is installed, grouped by runtime.
    ///
    /// Returns nil when the index cannot be trusted — the devices directory is
    /// missing or unreadable, no runtimes were found, or a `device.plist`
    /// failed to parse. The caller falls back to `simctl`.
    ///
    /// Unavailable devices are omitted rather than reported: deciding *why* a
    /// device is unusable is CoreSimulator's matching policy, not something to
    /// reimplement. Callers that need the unavailable list (`nimbus devices
    /// --all`) go to simctl.
    static func listAvailableDevices(
        devicesDirectory: String? = nil,
        runtimeDirectories: [String]? = nil
    ) -> [(runtime: String, devices: [SimulatorManager.Device])]? {
        let fm = FileManager.default
        let devicesPath = devicesDirectory ?? defaultDevicesDirectory
        guard let children = try? fm.contentsOfDirectory(atPath: devicesPath) else { return nil }

        let installed = installedRuntimeIdentifiers(in: runtimeDirectories ?? defaultRuntimeDirectories())
        guard !installed.isEmpty else { return nil }

        var byRuntime: [String: [SimulatorManager.Device]] = [:]

        for child in children {
            let plistPath = "\(devicesPath)/\(child)/device.plist"
            // No device.plist means this is not a device directory at all
            // (device_set.plist, .DS_Store, ...) — skip it rather than distrust
            // the index.
            guard let data = fm.contents(atPath: plistPath) else { continue }
            guard let entry = parseEntry(plistData: data) else { return nil }
            guard !entry.isDeleted, installed.contains(entry.runtime) else { continue }

            byRuntime[entry.runtime, default: []].append(
                SimulatorManager.Device(
                    udid: entry.udid,
                    name: entry.name,
                    state: stateName(entry.state),
                    isAvailable: true,
                    availabilityError: nil
                )
            )
        }

        // Directory order is not meaningful, and device choice must be stable
        // across invocations, so sort by name and break ties on UDID.
        return byRuntime
            .sorted { $0.key < $1.key }
            .map { entry in
                let devices = entry.value.sorted {
                    $0.name == $1.name ? $0.udid < $1.udid : $0.name < $1.name
                }
                return (runtime: entry.key, devices: devices)
            }
    }
}
