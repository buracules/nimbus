import Foundation

/// The outcome of matching a configured device against the simulators that
/// exist on this machine.
///
/// Every line a caller might want to print is derivable from these fields.
/// Choosing a device and telling a human about it are two different jobs, and
/// only the first one belongs here.
struct DeviceResolution: Codable {
    let device: SimulatorManager.Device
    let runtime: String
    /// The device name that was asked for, if one was configured.
    let requestedName: String?
    /// False when the requested name did not match and something else was used.
    /// True when nothing was requested — there was no request to miss.
    let matchedRequest: Bool
    /// Names close to the request, populated only when the request fell back.
    let suggestions: [String]
}

/// Decides which simulator a command targets. Matching policy lives here;
/// asking a human lives with whoever has a human.
enum DeviceResolver {
    /// Match the configured device against the simulators that exist.
    ///
    /// - Returns: the resolution, or nil when there are no simulators at all.
    static func resolveDevice(config: NimbusConfig) throws -> DeviceResolution? {
        // One enumeration serves the match, the fallback and the suggestions.
        let catalog = try SimulatorManager.availableDevices()

        guard let found = SimulatorManager.findDeviceWithFallback(
            in: catalog.groups,
            name: config.device,
            os: config.os
        ) else {
            return nil
        }

        let requestedName = config.device
        let matchedRequest = requestedName.map { $0 == found.device.name } ?? true

        var suggestions: [String] = []
        if let requestedName, !matchedRequest {
            suggestions = SimulatorManager.suggestDevices(
                in: catalog.groups,
                for: requestedName,
                os: config.os
            )
        }

        return DeviceResolution(
            device: found.device,
            runtime: found.runtime,
            requestedName: requestedName,
            matchedRequest: matchedRequest,
            suggestions: suggestions
        )
    }
}
