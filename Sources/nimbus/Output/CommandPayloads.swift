import Foundation

/// What each command puts in the envelope's `data` under `--json`.
///
/// These are compositions, not models. Every field is either a value core
/// already returns (`DeviceResolution`, `BuildResult`, `CapturedFile`,
/// `ShutdownOutcome`, `Device`) or a plain string naming what the command was
/// asked to do. Nothing here restates a fact core owns in a different shape,
/// because two shapes for one fact is two things to keep true.
///
/// `resolution` is optional only because a human picking from the interactive
/// menu produces no resolution to report. `--json` forces non-interactive
/// selection, so under `--json` the key is always present.

// MARK: - Build family

struct BuildPayload: Encodable {
    let scheme: String?
    let configuration: String?
    let resolution: DeviceResolution?
    let build: BuildResult
}

struct TestPayload: Encodable {
    let scheme: String?
    let configuration: String?
    let resolution: DeviceResolution?
    let test: BuildResult
}

struct CleanPayload: Encodable {
    let scheme: String?
    let configuration: String?
    let clean: BuildResult
}

struct RunPayload: Encodable {
    /// The app that was installed and launched.
    struct App: Encodable {
        let path: String
        let bundleID: String
    }

    let scheme: String?
    let configuration: String?
    let resolution: DeviceResolution?
    let build: BuildResult
    let app: App
}

// MARK: - Devices

struct DevicesPayload: Encodable {
    struct RuntimeGroup: Encodable {
        /// The runtime identifier, e.g. `com.apple.CoreSimulator.SimRuntime.iOS-26-2`.
        let runtime: String
        /// The same runtime as a human reads it, e.g. `iOS 26.2`.
        let name: String
        let devices: [SimulatorManager.Device]
    }

    let runtimes: [RuntimeGroup]
}

// MARK: - Init

struct InitPayload: Encodable {
    let path: String
    let config: NimbusConfig
}

// MARK: - Sim family

struct SimCapturePayload: Encodable {
    let resolution: DeviceResolution?
    let file: SimulatorControl.CapturedFile
}

struct SimOpenURLPayload: Encodable {
    let resolution: DeviceResolution?
    let url: String
}

struct SimPushPayload: Encodable {
    let resolution: DeviceResolution?
    let bundleID: String?
    let payload: String
}

struct SimPrivacyPayload: Encodable {
    let resolution: DeviceResolution?
    let action: SimulatorControl.PrivacyAction
    let service: String
    let bundleID: String?
}

struct SimAppearancePayload: Encodable {
    let resolution: DeviceResolution?
    /// The appearance now in effect, as simctl reports it.
    let appearance: String
}

struct SimStatusBarPayload: Encodable {
    let resolution: DeviceResolution?
    let cleared: Bool
    /// The simctl flag pairs that were applied; empty when cleared.
    let overrides: [String]
}

struct SimLocationPayload: Encodable {
    let resolution: DeviceResolution?
    let cleared: Bool
    let latitude: Double?
    let longitude: Double?
}

struct SimShutdownPayload: Encodable {
    let devices: [SimulatorControl.ShutdownOutcome]
}
