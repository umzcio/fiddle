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

struct AppPrefs: Codable, Equatable {
    var launchAtLogin: Bool
    var menuBarOnly: Bool
    var soundOnClick: Bool
    var skin: String
    var device: String
    var interfaceMode: String

    static let `default` = AppPrefs(launchAtLogin: false, menuBarOnly: false, soundOnClick: false, skin: "red", device: "mouse", interfaceMode: "advanced")
}

extension AppPrefs {
    private enum CodingKeys: String, CodingKey { case launchAtLogin, menuBarOnly, soundOnClick, skin, device, interfaceMode }

    // Tolerate prefs saved before `skin`, `device`, or `interfaceMode` existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
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
        macros: [],
        keyboard: KeyboardConfig(combo: "Space", intervalMs: 1000, repeat: .until, times: 50),
        profiles: []
    )

    private enum CodingKeys: String, CodingKey { case clicker, jiggler, prefs, wakeLock, antiAFK, recording, macros, keyboard, profiles }

    init(clicker: ClickerConfig, jiggler: JigglerConfig, prefs: AppPrefs, wakeLock: WakeLockConfig, antiAFK: AntiAFKConfig, recording: [RecordedEvent], macros: [Macro], keyboard: KeyboardConfig, profiles: [Profile]) {
        self.clicker = clicker; self.jiggler = jiggler; self.prefs = prefs
        self.wakeLock = wakeLock; self.antiAFK = antiAFK; self.recording = recording
        self.macros = macros; self.keyboard = keyboard; self.profiles = profiles
    }

    // Tolerate settings saved before `prefs`, `wakeLock`, `antiAFK`, `recording`, `macros`, or `keyboard` existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clicker = try c.decode(ClickerConfig.self, forKey: .clicker)
        jiggler = try c.decode(JigglerConfig.self, forKey: .jiggler)
        prefs = try c.decodeIfPresent(AppPrefs.self, forKey: .prefs) ?? .default
        wakeLock = try c.decodeIfPresent(WakeLockConfig.self, forKey: .wakeLock) ?? WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: false)
        antiAFK  = try c.decodeIfPresent(AntiAFKConfig.self,  forKey: .antiAFK)  ?? AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true)
        recording = try c.decodeIfPresent([RecordedEvent].self, forKey: .recording) ?? []
        macros = try c.decodeIfPresent([Macro].self, forKey: .macros) ?? []
        keyboard = try c.decodeIfPresent(KeyboardConfig.self, forKey: .keyboard) ?? KeyboardConfig(combo: "Space", intervalMs: 1000, repeat: .until, times: 50)
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
    }
}

/// Loads and persists `Settings` as JSON in UserDefaults.
final class SettingsStore {
    private static let key = "fiddle.settings.v1"
    private let defaults: UserDefaults
    private(set) var settings: Settings
    private let log = Logger(subsystem: "app.fiddle.Fiddle", category: "settings")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                self.settings = try JSONDecoder().decode(Settings.self, from: data)
            } catch {
                self.settings = .default
                log.error("settings decode failed, falling back to defaults: \(String(describing: error), privacy: .public)")
                defaults.set(data, forKey: Self.key + ".backup")
            }
        } else {
            self.settings = .default
        }
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
    func setMacros(_ macros: [Macro]) { settings.macros = macros; save() }

    func setPref(_ key: String, _ value: PrefValue) {
        switch (key, value) {
        case ("launchAtLogin", .bool(let b)): settings.prefs.launchAtLogin = b
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
