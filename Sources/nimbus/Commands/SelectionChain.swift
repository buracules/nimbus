import Foundation

/// Which layer supplied the device in a resolved config.
///
/// This is part of the `--json` contract for `nimbus use`, so the raw values are
/// stable. Add cases freely, rename them never.
enum DeviceSource: String, Encodable {
    /// A `--device` flag or a `nimbus use` argument on this invocation.
    case flag
    /// A selection pinned to this project with `nimbus use`.
    case state
    /// The project's `nimbus.yml`.
    case project
    /// `~/.config/nimbus/config.yml`.
    case global
    /// Nothing named a device; `DeviceResolver` picks one.
    case unset
}

/// A merged config, plus the facts about *how* the device was chosen that a user
/// cannot see from the config alone.
struct ConfigResolution {
    var config: NimbusConfig
    let projectRoot: String
    /// The `nimbus.yml` that contributed, if any. Carried so a caller can name
    /// it under `--verbose` without reading the filesystem a second time.
    let projectConfigPath: String?
    /// Whether the global config file contributed anything.
    let hasGlobalConfig: Bool
    let deviceSource: DeviceSource
    /// The device named in this project's `nimbus.yml` that the pinned
    /// selection is overriding. Nil when nothing is being shadowed.
    let shadowedProjectDevice: String?
    /// The pinned selection, when there was a usable one.
    let storedSelection: StoredSelection?
    /// Why a stored selection was ignored, when there was a file but it could
    /// not be used.
    let stateNote: String?
}

extension ConfigResolution {
    /// The `--verbose` account of which files were consulted.
    ///
    /// A store file that could not be used is reported here rather than
    /// swallowed: reading never fails a command, so this line is the only place
    /// a user finds out the selection they pinned is being ignored.
    func narrateLayers(verbose: Bool) {
        if hasGlobalConfig {
            Console.verbose("Loaded global config: \(ConfigLoader.globalConfigPath)", isVerbose: verbose)
        }
        if let projectConfigPath {
            Console.verbose("Loaded project config: \(projectConfigPath)", isVerbose: verbose)
        }
        if let stateNote {
            Console.verbose("Ignoring stored simulator selection: \(stateNote)", isVerbose: verbose)
        }
        if let stored = storedSelection {
            Console.verbose(
                "Pinned simulator for \(projectRoot): \(stored.device)"
                    + (stored.os.map { " (OS \($0))" } ?? ""),
                isVerbose: verbose
            )
        }
    }
}

/// Assembles the configuration layers and reports which one won.
///
/// ```
/// CLI flags > sticky state > project nimbus.yml > global config
/// ```
///
/// State ranks **above** project config on purpose. If it ranked below,
/// `nimbus use "iPhone 17 Pro"` would be a silent no-op in any project whose
/// `nimbus.yml` names a `device:` — a verb that says "use this" and does not is
/// dishonest.
///
/// The price of that ordering is that a committed `device:` can stop taking
/// effect without the file changing, so `shadowedProjectDevice` carries the fact
/// out of here for a caller to say out loud. That notice is a requirement of the
/// ordering, not a nicety.
enum SelectionChain {
    static func resolve(
        cli: NimbusConfig,
        directory: String = FileManager.default.currentDirectoryPath,
        stateDirectory: String = SelectionStore.defaultDirectory
    ) throws -> ConfigResolution {
        let global = try ConfigLoader.loadGlobal()
        let projectConfigPath = ConfigLoader.findConfigFile(from: directory)
        let project = try projectConfigPath.map { try ConfigLoader.loadFile(at: $0) } ?? .empty
        let projectRoot = ProjectIdentity.projectRoot(from: directory)
        let stored = SelectionStore.load(projectRoot: projectRoot, directory: stateDirectory)

        let state = stored.selection.map { NimbusConfig(device: $0.device, os: $0.os) } ?? .empty
        let combined = combine(global: global, project: project, state: state, cli: cli)

        return ConfigResolution(
            config: combined.config,
            projectRoot: projectRoot,
            projectConfigPath: projectConfigPath,
            hasGlobalConfig: global != .empty,
            deviceSource: combined.source,
            shadowedProjectDevice: combined.shadowedProjectDevice,
            storedSelection: stored.selection,
            stateNote: stored.note
        )
    }

    /// The merge and the provenance, given layers that are already loaded.
    ///
    /// Split out from `resolve` so the ordering can be asserted without touching
    /// this machine's real config files.
    static func combine(
        global: NimbusConfig,
        project: NimbusConfig,
        state: NimbusConfig,
        cli: NimbusConfig
    ) -> (config: NimbusConfig, source: DeviceSource, shadowedProjectDevice: String?) {
        let config = global
            .merging(with: project)
            .merging(with: state)
            .merging(with: cli)

        let source: DeviceSource
        if cli.device != nil {
            source = .flag
        } else if state.device != nil {
            source = .state
        } else if project.device != nil {
            source = .project
        } else if global.device != nil {
            source = .global
        } else {
            source = .unset
        }

        let shadowed = source == .state ? project.device : nil
        return (config, source, shadowed)
    }

    /// How a source reads in a sentence about the device.
    static func describe(_ source: DeviceSource) -> String {
        switch source {
        case .flag: return "this command's flags"
        case .state: return "'nimbus use'"
        case .project: return "nimbus.yml"
        case .global: return "global config"
        case .unset: return "nothing — nimbus picks an available simulator"
        }
    }
}
