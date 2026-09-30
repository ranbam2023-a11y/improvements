//
//  Model.swift — augments, their settings, and the persisted app state.
//
//  An "augment" is one small improvement to macOS. Each augment has a
//  description, a list of typed settings, an on/off state, and optional
//  requirements it can check and fix for you.
//

import Foundation
import AppKit
import Combine
import ServiceManagement

// MARK: - Setting values

/// A type-erased, codable setting value.
enum SettingValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case bool, int, double, string }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let v):   try c.encode(Kind.bool, forKey: .type);   try c.encode(v, forKey: .value)
        case .int(let v):    try c.encode(Kind.int, forKey: .type);    try c.encode(v, forKey: .value)
        case .double(let v): try c.encode(Kind.double, forKey: .type); try c.encode(v, forKey: .value)
        case .string(let v): try c.encode(Kind.string, forKey: .type); try c.encode(v, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .bool:   self = .bool(try c.decode(Bool.self, forKey: .value))
        case .int:    self = .int(try c.decode(Int.self, forKey: .value))
        case .double: self = .double(try c.decode(Double.self, forKey: .value))
        case .string: self = .string(try c.decode(String.self, forKey: .value))
        }
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v):    return Double(v)
        default:             return nil
        }
    }
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

// MARK: - Setting description

/// Describes one editable setting; the UI builds the right control from `kind`.
struct SettingSpec: Identifiable {
    enum Kind {
        case toggle
        case stepper(ClosedRange<Int>, step: Int)
        case slider(ClosedRange<Double>, step: Double, format: String)
        case text(placeholder: String)
        case shortcut(placeholder: String)
        case choice([String])
    }

    let id: String
    let label: String
    let group: String
    let help: String?
    let kind: Kind
    let defaultValue: SettingValue

    init(_ id: String, _ label: String, group: String = "Settings", help: String? = nil,
         kind: Kind, default defaultValue: SettingValue) {
        self.id = id
        self.label = label
        self.group = group
        self.help = help
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

/// Something the augment needs in order to work, which it can try to fix.
struct Requirement: Identifiable {
    let id: String
    let text: String
    let isSatisfied: () -> Bool
    let fixLabel: String?
    let fix: (() -> Void)?
}

// MARK: - Augment

class Augment: ObservableObject, Identifiable {
    let id: String
    let name: String
    let icon: String
    let tagline: String
    let description: String
    let specs: [SettingSpec]

    /// Things that must be true for this augment to work well.
    var requirements: [Requirement] { [] }

    /// The settings to show. Augments may hide settings that don't apply to the
    /// current mode; the UI rebuilds itself when a choice like that changes.
    var visibleSpecs: [SettingSpec] { specs }

    /// Called whenever the user changes anything, so the app can persist it.
    var onChange: (() -> Void)?

    @Published var enabled: Bool = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { start() } else { stop() }
            onChange?()
        }
    }

    @Published var config: [String: SettingValue] = [:] {
        didSet {
            didUpdateConfig()
            onChange?()
        }
    }

    @Published var status: String = "Off"
    @Published var lastEvent: String?

    init(id: String, name: String, icon: String, tagline: String,
         description: String, specs: [SettingSpec]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.tagline = tagline
        self.description = description
        self.specs = specs
    }

    // Subclasses override the lifecycle hooks.
    func start() {}
    func stop() {}
    func didUpdateConfig() {}

    /// Runs the augment's action once, as if the gesture had just happened.
    /// Used by the `--fire` CLI flag, which is handy for testing.
    func fireOnce() {}

    // MARK: Typed config access (falls back to the spec's default)

    func spec(_ key: String) -> SettingSpec? { specs.first { $0.id == key } }

    func bool(_ key: String) -> Bool {
        config[key]?.boolValue ?? spec(key)?.defaultValue.boolValue ?? false
    }
    func int(_ key: String) -> Int {
        config[key]?.intValue ?? spec(key)?.defaultValue.intValue ?? 0
    }
    func double(_ key: String) -> Double {
        config[key]?.doubleValue ?? spec(key)?.defaultValue.doubleValue ?? 0
    }
    func string(_ key: String) -> String {
        config[key]?.stringValue ?? spec(key)?.defaultValue.stringValue ?? ""
    }

    func set(_ key: String, _ value: SettingValue) {
        config[key] = value
    }
}

// MARK: - Persistence

private struct PersistedAugment: Codable {
    var config: [String: SettingValue]
}

private struct Persisted: Codable {
    var augments: [String: PersistedAugment]
}

// MARK: - The app model

final class AppModel: ObservableObject {
    let augments: [Augment]

    private static let selectionKey = "selectedAugment"

    @Published var selection: String? = "highfive" {
        didSet { UserDefaults.standard.set(selection, forKey: Self.selectionKey) }
    }
    @Published var launchAtLogin: Bool = false
    @Published var message: String?

    private let configURL: URL
    private var pendingSave: DispatchWorkItem?

    init() {
        augments = [HighFiveAugment(), MenuTypeAugment()]

        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        configURL = support.appendingPathComponent("Improvements/config.json")

        for augment in augments {
            augment.onChange = { [weak self] in self?.scheduleSave() }
        }

        if let remembered = UserDefaults.standard.string(forKey: Self.selectionKey) {
            selection = remembered
        }

        load()
        refreshLoginItem()

        // Anything not enabled keeps nothing on disk.
        for augment in augments where !augment.enabled {
            AugmentData.removeAll(for: augment.id)
        }

        Log.write("app started, augments=\(augments.map { $0.id }.joined(separator: ","))")
    }

    var selectedAugment: Augment? { augments.first { $0.id == selection } }

    func setEnabled(_ augment: Augment, _ value: Bool) {
        guard augment.enabled != value else { return }
        augment.enabled = value
        // A disabled augment stores nothing, so drop whatever it had.
        if !value { AugmentData.removeAll(for: augment.id) }
    }

    // MARK: Persisting

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    func save() {
        // Only enabled augments are stored. A disabled augment keeps nothing on
        // disk — no settings, no state — so turning it off really turns it off.
        var dictionary: [String: PersistedAugment] = [:]
        for augment in augments where augment.enabled {
            dictionary[augment.id] = PersistedAugment(config: augment.config)
        }

        guard !dictionary.isEmpty else {
            try? FileManager.default.removeItem(at: configURL)
            return
        }

        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Persisted(augments: dictionary)).write(to: configURL, options: .atomic)
        } catch {
            Log.write("save failed: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        // Anything in the file is by definition an enabled augment.
        for augment in augments {
            guard let saved = root.augments[augment.id] else { continue }
            if !saved.config.isEmpty { augment.config = saved.config }
            augment.enabled = true
        }
    }

    // MARK: Launch at login

    func refreshLoginItem() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = "Could not change the login item: \(error.localizedDescription)"
            Log.write("login item error: \(error.localizedDescription)")
        }
        refreshLoginItem()
    }
}

// MARK: - Legacy app cleanup

/// A standalone app this one replaces. If it's still installed you'd get two
/// copies of the same behaviour, so the General page offers to remove it.
struct LegacyInstall: Identifiable {
    let id: String
    let buttonTitle: String
    let detail: String
    let isInstalled: () -> Bool
    let remove: () -> Void
}

enum Legacy {
    static var all: [LegacyInstall] { [highFive, menuType] }

    // MARK: High Five

    private static var highFiveAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.ranbam.highfive.plist"
    }
    private static var highFiveAppPaths: [String] {
        ["/Applications/HighFive.app", NSHomeDirectory() + "/Applications/HighFive.app"]
    }

    static let highFive = LegacyInstall(
        id: "highfive",
        buttonTitle: "Remove old HighFive",
        detail: "The old standalone HighFive agent is still installed, so it would react to the same gesture a second time.",
        isInstalled: {
            let fm = FileManager.default
            return fm.fileExists(atPath: highFiveAgentPath)
                || highFiveAppPaths.contains { fm.fileExists(atPath: $0) }
        },
        remove: {
            let uid = getuid()
            Log.run("/bin/launchctl", ["bootout", "gui/\(uid)/com.ranbam.highfive"])
            Log.run("/bin/launchctl", ["bootout", "gui/\(uid)", highFiveAgentPath])
            try? FileManager.default.removeItem(atPath: highFiveAgentPath)
            for path in highFiveAppPaths { try? FileManager.default.removeItem(atPath: path) }
            Log.write("removed legacy HighFive agent/app")
        }
    )

    // MARK: MenuType

    private static var menuTypeAppPaths: [String] {
        ["/Applications/MenuType.app", NSHomeDirectory() + "/Applications/MenuType.app"]
    }

    static let menuType = LegacyInstall(
        id: "menutype",
        buttonTitle: "Remove old MenuType",
        detail: "The standalone MenuType app is still installed, so you'd get two typing trainers in the menu bar.",
        isInstalled: { menuTypeAppPaths.contains { FileManager.default.fileExists(atPath: $0) } },
        remove: {
            // Quit only the standalone app, by bundle identifier.
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.ranbam.menutype") {
                app.terminate()
            }
            for path in menuTypeAppPaths { try? FileManager.default.removeItem(atPath: path) }
            Log.write("removed legacy MenuType app")
        }
    )
}
