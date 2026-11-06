//
//  Settings.swift
//  Fiddle
//
//  The single Codable value that persists user configuration. Hotkey bindings
//  are persisted by the KeyboardShortcuts package; the store only keeps a
//  sealed copy of them in HotkeyTrust to detect changes made outside fiddle.
//

import CryptoKit
import Foundation
import os

/// Decodes an array element by element, dropping elements that fail, so one
/// corrupt entry cannot discard every profile, macro, and recorded event at
/// once when the settings blob loads.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    /// Consumes one element of any shape to advance past an undecodable entry.
    private struct Discard: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            let index = container.currentIndex
            if let value = try? container.decode(Element.self) {
                out.append(value)
            } else {
                _ = try? container.decode(Discard.self)
            }
            if container.currentIndex == index { break }   // cannot advance; bail
        }
        elements = out
    }
}

// Note: launch-at-login is intentionally NOT stored here. SMAppService owns
// that state (the user can change it in System Settings behind our back), so
// the UI always reads LoginItem.isEnabled live; a stored copy only drifts.
struct AppPrefs: Codable, Equatable {
    var menuBarOnly: Bool
    var soundOnClick: Bool
    var skin: String
    var device: String
    var interfaceMode: String
    var lastMode: String
    /// Id of the macro most recently played, so the Start/Stop hotkey can
    /// replay it. Empty until a macro has been played. Not exposed to the UI.
    var lastMacroId: String

    static let `default` = AppPrefs(menuBarOnly: false, soundOnClick: false, skin: "red", device: "mouse", interfaceMode: "advanced", lastMode: "clicker", lastMacroId: "")
}

extension AppPrefs {
    private enum CodingKeys: String, CodingKey { case menuBarOnly, soundOnClick, skin, device, interfaceMode, lastMode, lastMacroId }

    // Tolerate prefs saved before `skin`, `device`, `interfaceMode`, or
    // `lastMode` existed. Older blobs also contain a `launchAtLogin` key;
    // it is simply ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarOnly   = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly) ?? false
        soundOnClick  = try c.decodeIfPresent(Bool.self, forKey: .soundOnClick) ?? false
        skin          = try c.decodeIfPresent(String.self, forKey: .skin) ?? "red"
        device        = try c.decodeIfPresent(String.self, forKey: .device) ?? "mouse"
        interfaceMode = try c.decodeIfPresent(String.self, forKey: .interfaceMode) ?? "advanced"
        lastMode      = try c.decodeIfPresent(String.self, forKey: .lastMode) ?? "clicker"
        lastMacroId   = try c.decodeIfPresent(String.self, forKey: .lastMacroId) ?? ""
    }
}

struct Settings: Codable, Equatable {
    var clicker: ClickerConfig
    var jiggler: JigglerConfig
    var prefs: AppPrefs
    var wakeLock: WakeLockConfig
    var antiAFK: AntiAFKConfig
    var recording: [RecordedEvent]
    var recorder: RecorderConfig
    var macros: [Macro]
    var keyboard: KeyboardConfig
    var profiles: [Profile]

    /// Matches the initial values shown in the web UI.
    static let `default` = Settings(
        clicker: ClickerConfig(intervalMs: 100, button: .left, clickType: .single, repeat: .until, times: 50, position: .current, x: 640, y: 480),
        jiggler: JigglerConfig(intervalSec: 30, distancePx: 40, mode: .zen, keepAwake: true, idleOnly: true),
        prefs: .default,
        wakeLock: WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: false),
        antiAFK: AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true),
        recording: [],
        recorder: RecorderConfig(repeat: .until, times: 5),
        macros: [],
        keyboard: KeyboardConfig(combo: "Space", intervalMs: 1000, repeat: .until, times: 50),
        profiles: []
    )

    private enum CodingKeys: String, CodingKey { case clicker, jiggler, prefs, wakeLock, antiAFK, recording, recorder, macros, keyboard, profiles }

    init(clicker: ClickerConfig, jiggler: JigglerConfig, prefs: AppPrefs, wakeLock: WakeLockConfig, antiAFK: AntiAFKConfig, recording: [RecordedEvent], recorder: RecorderConfig, macros: [Macro], keyboard: KeyboardConfig, profiles: [Profile]) {
        self.clicker = clicker; self.jiggler = jiggler; self.prefs = prefs
        self.wakeLock = wakeLock; self.antiAFK = antiAFK; self.recording = recording
        self.recorder = recorder; self.macros = macros; self.keyboard = keyboard; self.profiles = profiles
    }

    // Tolerate settings saved before `prefs`, `wakeLock`, `antiAFK`, `recording`, `recorder`, `macros`, or `keyboard` existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clicker = try c.decodeIfPresent(ClickerConfig.self, forKey: .clicker) ?? Settings.default.clicker
        jiggler = try c.decodeIfPresent(JigglerConfig.self, forKey: .jiggler) ?? Settings.default.jiggler
        prefs = try c.decodeIfPresent(AppPrefs.self, forKey: .prefs) ?? .default
        wakeLock = try c.decodeIfPresent(WakeLockConfig.self, forKey: .wakeLock) ?? WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: false)
        antiAFK  = try c.decodeIfPresent(AntiAFKConfig.self,  forKey: .antiAFK)  ?? AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true)
        // Arrays decode lossily: a single corrupt element is dropped instead of
        // failing the whole settings decode (which would reset everything).
        recording = (try? c.decode(LossyArray<RecordedEvent>.self, forKey: .recording))?.elements ?? []
        recorder = try c.decodeIfPresent(RecorderConfig.self, forKey: .recorder) ?? RecorderConfig(repeat: .until, times: 5)
        macros = (try? c.decode(LossyArray<Macro>.self, forKey: .macros))?.elements ?? []
        keyboard = try c.decodeIfPresent(KeyboardConfig.self, forKey: .keyboard) ?? KeyboardConfig(combo: "Space", intervalMs: 1000, repeat: .until, times: 50)
        profiles = (try? c.decode(LossyArray<Profile>.self, forKey: .profiles))?.elements ?? []
    }
}

/// Loads and persists `Settings` as JSON in UserDefaults, sealed with a
/// Keychain-held key (see SettingsSeal.swift).
final class SettingsStore {
    /// How settings that could not be verified came to be loaded.
    enum Adoption: Equatable {
        /// Brought over from fiddle's earlier bundle id, whose seal key this
        /// signing identity cannot read.
        case inherited
        /// Found without a valid seal under fiddle's own id (key deleted or
        /// unreadable).
        case unverified
    }

    private static let key = "fiddle.settings.v1"
    private static let sealKey = key + ".seal"
    private static let trustKey = key + ".trust"
    /// fiddle's bundle id before 1.1.0. Its settings are imported once.
    static let legacySuite = "edu.umontana.fiddle"

    private let defaults: UserDefaults
    private(set) var settings: Settings
    private(set) var trust: HotkeyTrust = .full
    /// True when the saved blob could not be decoded and defaults were used.
    /// The controller surfaces this to the user once, then acknowledges it.
    private(set) var didResetToDefaults = false
    /// True when the saved blob was changed outside fiddle and was discarded.
    /// Surfaced once like `didResetToDefaults`.
    private(set) var didRejectTamperedSettings = false
    /// Set when settings were loaded without a valid seal. Surfaced once.
    private(set) var adoption: Adoption?
    /// The Keychain key could not be read; changes this session are not saved,
    /// so a good sealed blob is never replaced by one the next launch rejects.
    var isSealUnavailable: Bool { sealingKey == nil }
    /// The XCTest host's throwaway store. Hotkey bindings live in the real
    /// defaults domain, so the controller must not enforce them against it.
    let isScratch: Bool
    private var sealingKey: SymmetricKey?
    private let log = Logger(subsystem: "com.zapps.fiddle", category: "settings")

    convenience init() {
        // As the XCTest host the app must not touch the user's real settings or
        // create the real Keychain key: an installed fiddle would then reject
        // its own settings at the next launch.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           let scratch = UserDefaults(suiteName: "com.zapps.fiddle.testhost") {
            scratch.removePersistentDomain(forName: "com.zapps.fiddle.testhost")
            self.init(defaults: scratch, keys: EphemeralSettingsKey(), isScratch: true)
            return
        }
        self.init(defaults: .standard, keys: KeychainSettingsKey(), legacy: UserDefaults(suiteName: Self.legacySuite))
    }

    init(defaults: UserDefaults, keys: SettingsKeyStore, legacy: UserDefaults? = nil, isScratch: Bool = false) {
        self.defaults = defaults
        self.isScratch = isScratch
        self.settings = .default
        let own = defaults.data(forKey: Self.key)
        let inherited = own == nil ? legacy?.data(forKey: Self.key) : nil

        switch keys.loadKey() {
        case .found(let key):
            sealingKey = key
            if let own {
                let state = defaults.data(forKey: Self.trustKey) ?? Data()
                if let seal = defaults.data(forKey: Self.sealKey),
                   SettingsSeal.verify(own, state: state, seal: seal, key: key),
                   let stored = try? JSONDecoder().decode(HotkeyTrust.self, from: state) {
                    settings = decode(own)
                    trust = stored
                } else {
                    // Defaults hold no planted target, so full trust is safe;
                    // the nil bindings make launch reset the hotkeys too.
                    log.error("settings seal did not verify; discarding the stored blob")
                    didRejectTamperedSettings = true
                    defaults.set(own, forKey: Self.key + ".rejected")
                    save()
                }
            } else if let inherited {
                adopt(inherited, as: .inherited)
                save()
            }
        case .missing:
            sealingKey = keys.createKey()
            if let own { adopt(own, as: .unverified) } else if let inherited { adopt(inherited, as: .inherited) }
            save()
        case .unavailable:
            log.error("settings seal key is unreadable; loading untrusted and not saving")
            if let own { adopt(own, as: .unverified) } else if let inherited { adopt(inherited, as: .inherited) }
        }
    }

    /// Load settings nobody can vouch for. They are kept, so nothing the user
    /// had is lost, but no hotkey may start a mode until the user starts it
    /// from fiddle's UI, and the hotkey bindings go back to their defaults.
    private func adopt(_ data: Data, as how: Adoption) {
        settings = decode(data)
        trust = .none
        if !didResetToDefaults { adoption = how }
    }

    private func decode(_ data: Data) -> Settings {
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            didResetToDefaults = true
            log.error("settings decode failed, falling back to defaults: \(String(describing: error), privacy: .public)")
            defaults.set(data, forKey: Self.key + ".backup")
            return .default
        }
    }

    func acknowledgeReset() { didResetToDefaults = false }
    func acknowledgeRejection() { didRejectTamperedSettings = false }
    func acknowledgeAdoption() { adoption = nil }

    /// Whether a hotkey may start this mode with its stored configuration.
    func isTrustedForHotkeys(_ mode: AutomationMode) -> Bool {
        trust.modes.contains(mode.rawValue)
    }

    /// The user started this mode from fiddle's UI, so the hotkeys may too.
    func trustForHotkeys(_ mode: AutomationMode) {
        guard !isTrustedForHotkeys(mode) else { return }
        trust.modes.append(mode.rawValue)
        save()
    }

    /// Remember the bindings fiddle just set or confirmed.
    func recordHotkeyBindings(_ bindings: [String: String]) {
        guard trust.bindings != bindings else { return }
        trust.bindings = bindings
        save()
    }

    func setClicker(_ config: ClickerConfig) {
        settings.clicker = config
        save()
    }

    func setJiggler(_ config: JigglerConfig) {
        settings.jiggler = config
        save()
    }

    func setWakeLock(_ config: WakeLockConfig) { settings.wakeLock = config; save() }
    func setAntiAFK(_ config: AntiAFKConfig) { settings.antiAFK = config; save() }
    func setRecording(_ events: [RecordedEvent]) { settings.recording = events; save() }
    func setRecorder(_ config: RecorderConfig) { settings.recorder = config; save() }
    func setMacros(_ macros: [Macro]) { settings.macros = macros; save() }

    func setPref(_ key: String, _ value: PrefValue) {
        switch (key, value) {
        case ("menuBarOnly", .bool(let b)):   settings.prefs.menuBarOnly = b
        case ("soundOnClick", .bool(let b)):  settings.prefs.soundOnClick = b
        case ("skin", .string(let s)):           settings.prefs.skin = s
        case ("device", .string(let s)):         settings.prefs.device = s
        case ("interfaceMode", .string(let s)):  settings.prefs.interfaceMode = s
        case ("lastMode", .string(let s)):       settings.prefs.lastMode = s
        case ("lastMacroId", .string(let s)):    settings.prefs.lastMacroId = s
        default: return
        }
        save()
    }

    func setKeyboard(_ config: KeyboardConfig) { settings.keyboard = config; save() }
    func setProfiles(_ profiles: [Profile]) { settings.profiles = profiles; save() }

    /// Batch several mutations into a single encode + write, for callers that
    /// change many fields at once (applying a profile re-encodes the whole
    /// blob, recording included, so one save instead of six matters).
    func update(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        save()
    }

    private func save() {
        guard let sealingKey else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(settings)
            let state = try encoder.encode(trust)
            defaults.set(data, forKey: Self.key)
            defaults.set(state, forKey: Self.trustKey)
            defaults.set(SettingsSeal.seal(data, state: state, key: sealingKey), forKey: Self.sealKey)
        } catch {
            log.error("settings encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}
