//
//  Settings.swift
//  Fiddle
//
//  The single Codable value that persists user configuration. Hotkey bindings
//  are persisted separately by the KeyboardShortcuts package, so they are not
//  duplicated here.
//

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

    static let `default` = AppPrefs(menuBarOnly: false, soundOnClick: false, skin: "red", device: "mouse", interfaceMode: "advanced")
}

extension AppPrefs {
    private enum CodingKeys: String, CodingKey { case menuBarOnly, soundOnClick, skin, device, interfaceMode }

    // Tolerate prefs saved before `skin`, `device`, or `interfaceMode` existed.
    // Older blobs also contain a `launchAtLogin` key; it is simply ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarOnly   = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly) ?? false
        soundOnClick  = try c.decodeIfPresent(Bool.self, forKey: .soundOnClick) ?? false
        skin          = try c.decodeIfPresent(String.self, forKey: .skin) ?? "red"
        device        = try c.decodeIfPresent(String.self, forKey: .device) ?? "mouse"
        interfaceMode = try c.decodeIfPresent(String.self, forKey: .interfaceMode) ?? "advanced"
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
        clicker = try c.decode(ClickerConfig.self, forKey: .clicker)
        jiggler = try c.decode(JigglerConfig.self, forKey: .jiggler)
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

/// Loads and persists `Settings` as JSON in UserDefaults.
final class SettingsStore {
    private static let key = "fiddle.settings.v1"
    private let defaults: UserDefaults
    private(set) var settings: Settings
    /// True when the saved blob could not be decoded and defaults were used.
    /// The controller surfaces this to the user once, then acknowledges it.
    private(set) var didResetToDefaults = false
    private let log = Logger(subsystem: "edu.umontana.fiddle", category: "settings")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                self.settings = try JSONDecoder().decode(Settings.self, from: data)
            } catch {
                self.settings = .default
                self.didResetToDefaults = true
                log.error("settings decode failed, falling back to defaults: \(String(describing: error), privacy: .public)")
                defaults.set(data, forKey: Self.key + ".backup")
            }
        } else {
            self.settings = .default
        }
    }

    func acknowledgeReset() { didResetToDefaults = false }

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
        default: return
        }
        save()
    }

    func setKeyboard(_ config: KeyboardConfig) { settings.keyboard = config; save() }
    func setProfiles(_ profiles: [Profile]) { settings.profiles = profiles; save() }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.key)
        } catch {
            log.error("settings encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}
