//
//  Protocol.swift
//  Fiddle
//
//  The typed contract between the web UI (running in a WKWebView) and the
//  native engine. This is a starter: the cases here mirror the bridge table
//  in CLAUDE.md exactly. Keep the two in sync.
//
//  Direction:
//    Command  = web  -> Swift   (decoded from message.body)
//    Event    = Swift -> web     (encoded, then handed to evaluateJavaScript)
//
//  The matching JS half (in Fiddle/UI/web/index.html) must:
//    - send:    window.webkit.messageHandlers.fiddle.postMessage({ type: "...", ... })
//    - receive: window.fiddleEvent = (e) => { switch (e.type) { ... } }
//

import Foundation

// MARK: - Shared enums

enum AutomationMode: String, Codable {
    case clicker
    case jiggler
    case wakeLock
    case antiAFK
    case recorder
    case macro
    case keyboard
}

enum MouseButton: String, Codable {
    case left
    case right
    case middle
}

enum ClickType: String, Codable {
    case single
    case double
}

enum RepeatMode: String, Codable {
    case times   // stop after `times` clicks
    case until   // run until stopped
}

enum PositionMode: String, Codable {
    case current // click wherever the cursor is
    case fixed   // click at a fixed x, y
}

enum JiggleStyle: String, Codable {
    case zen     // move and return so the cursor does not visibly drift
    case visible // leave the cursor where it lands
}

enum HotkeyAction: String, Codable {
    case startStop
    case pickPosition
    case toggleJiggler
    case panic
}

enum SettingsPane: String, Codable {
    case accessibility
    case inputMonitoring
}

enum WindowAction: String, Codable {
    case minimize, close, help, fit, showWindow, quit, checkForUpdates
}

enum RunStatus: String, Codable {
    case idle
    case running
}

// MARK: - Config payloads

struct ClickerConfig: Codable, Equatable {
    var intervalMs: Int
    var button: MouseButton
    var clickType: ClickType
    var `repeat`: RepeatMode
    var times: Int
    var position: PositionMode
    var x: Int
    var y: Int
    // UI-only: simple mode / popover express speed as a continuous rate
    // (clicks per second/minute). The engine still drives off intervalMs;
    // these persist so the rate UI restores. Default 5 per minute.
    var rate: Int = 5
    var rateUnit: String = "minute"
}

struct JigglerConfig: Codable, Equatable {
    var intervalSec: Int
    var distancePx: Int
    var mode: JiggleStyle
    var keepAwake: Bool
    var idleOnly: Bool
}

struct WakeLockConfig: Codable, Equatable {
    var keepDisplayAwake: Bool
    var keepSystemAwake: Bool
}

struct AntiAFKConfig: Codable, Equatable {
    var intervalSec: Int
    var distancePx: Int
    var keepAwake: Bool
}

struct KeyboardConfig: Codable, Equatable {
    var combo: String          // HotkeyCombo token, e.g. "cmd+KeyS", "Space", "F5"
    var intervalMs: Int
    var `repeat`: RepeatMode
    var times: Int
}

/// The config that rides along with `start` and `updateConfig`. Which case is
/// present is determined by the sibling `mode` field on the command.
enum Config: Equatable {
    case clicker(ClickerConfig)
    case jiggler(JigglerConfig)
    case wakeLock(WakeLockConfig)
    case antiAFK(AntiAFKConfig)
    case recorder(RecorderConfig)
    case macro(MacroConfig)
    case keyboard(KeyboardConfig)
}

/// A preference value can arrive as a bool, int, or string from JS. It only
/// rides the web-to-Swift Command, so it is Decodable-only.
enum PrefValue: Decodable, Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported pref value")
    }
}

// MARK: - Command (web -> Swift)

enum Command: Equatable {
    case ready
    case start(mode: AutomationMode, config: Config)
    case stop
    case updateConfig(mode: AutomationMode, config: Config)
    case pickPosition(purpose: String?)
    case setHotkey(action: HotkeyAction, combo: String)
    /// Restore every hotkey binding to its default. The defaults live with
    /// HotkeyManager (the single source of truth), not in the web layer.
    case resetHotkeys
    case setPref(key: String, value: PrefValue)
    case checkPermissions
    case openSettings(pane: SettingsPane)
    case window(action: WindowAction)
    case recordStart
    case recordStop
    case clearRecording
    case saveMacros(macros: [Macro])
    case saveProfiles(profiles: [Profile])
    case applyProfile(id: String)
}

extension Command: Decodable {
    private enum Keys: String, CodingKey {
        case type, mode, config, action, combo, key, value, pane, purpose, macros, profiles, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)

        switch type {
        case "ready":            self = .ready
        case "stop":             self = .stop
        case "pickPosition":     self = .pickPosition(purpose: try c.decodeIfPresent(String.self, forKey: .purpose))
        case "checkPermissions": self = .checkPermissions
        case "saveMacros":       self = .saveMacros(macros: try c.decode([Macro].self, forKey: .macros))
        case "saveProfiles":     self = .saveProfiles(profiles: try c.decode([Profile].self, forKey: .profiles))
        case "applyProfile":     self = .applyProfile(id: try c.decode(String.self, forKey: .id))

        case "start":
            let mode = try c.decode(AutomationMode.self, forKey: .mode)
            self = .start(mode: mode, config: try Command.config(for: mode, from: c))

        case "updateConfig":
            let mode = try c.decode(AutomationMode.self, forKey: .mode)
            self = .updateConfig(mode: mode, config: try Command.config(for: mode, from: c))

        case "setHotkey":
            self = .setHotkey(
                action: try c.decode(HotkeyAction.self, forKey: .action),
                combo: try c.decode(String.self, forKey: .combo)
            )

        case "setPref":
            self = .setPref(
                key: try c.decode(String.self, forKey: .key),
                value: try c.decode(PrefValue.self, forKey: .value)
            )

        case "openSettings":
            self = .openSettings(pane: try c.decode(SettingsPane.self, forKey: .pane))

        case "window":
            self = .window(action: try c.decode(WindowAction.self, forKey: .action))

        case "recordStart":      self = .recordStart
        case "recordStop":       self = .recordStop
        case "clearRecording":   self = .clearRecording
        case "resetHotkeys":     self = .resetHotkeys

        default:
            throw DecodingError.dataCorruptedError(
                forKey: Keys.type, in: c,
                debugDescription: "Unknown command type: \(type)"
            )
        }
    }

    private static func config(
        for mode: AutomationMode,
        from c: KeyedDecodingContainer<Keys>
    ) throws -> Config {
        switch mode {
        case .clicker:  return .clicker(try c.decode(ClickerConfig.self, forKey: .config))
        case .jiggler:  return .jiggler(try c.decode(JigglerConfig.self, forKey: .config))
        case .wakeLock: return .wakeLock(try c.decode(WakeLockConfig.self, forKey: .config))
        case .antiAFK:  return .antiAFK(try c.decode(AntiAFKConfig.self, forKey: .config))
        case .recorder: return .recorder(try c.decode(RecorderConfig.self, forKey: .config))
        case .macro:    return .macro(try c.decode(MacroConfig.self, forKey: .config))
        case .keyboard: return .keyboard(try c.decode(KeyboardConfig.self, forKey: .config))
        }
    }
}

// MARK: - Event (Swift -> web)

enum Event {
    case status(RunStatus)
    case permissions(accessibility: Bool, inputMonitoring: Bool)
    case positionPicked(x: Int, y: Int)
    case error(message: String)
    /// Pushes a saved config into the web UI so the controls reflect persisted
    /// state (sent on `ready`). The JS half mirrors this as `applyConfig`.
    case config(mode: AutomationMode, config: Config)
    /// Pushes saved app preferences into the web UI (sent on `ready`).
    case prefs(launchAtLogin: Bool, menuBarOnly: Bool, soundOnClick: Bool, skin: String, device: String, interfaceMode: String)
    /// Pushes the current global-hotkey bindings to the web UI so the keycaps
    /// reflect persisted state. Keys are HotkeyAction raw values; values are
    /// combo token strings (see HotkeyCombo). Sent on `ready` and after each
    /// successful rebind.
    case hotkeys(bindings: [String: String])
    /// Pushes the recorder's state and step list to the web UI. `active` is true
    /// while capturing. Sent on recordStart/recordStop/clearRecording and ready.
    case recording(active: Bool, steps: [DisplayStep])
    /// Pushes the saved macro library to the web UI (sent on ready and after saveMacros).
    case macros(list: [Macro])
    /// Pushes the saved profile library (sent on ready and after saveProfiles).
    case profiles(list: [Profile])
    /// One activity-log line for the Activity Log view (session-only on the web).
    case log(message: String, level: String)
}

extension Event: Encodable {
    private enum Keys: String, CodingKey {
        case type, value, accessibility, inputMonitoring, x, y, action, message, mode, config, launchAtLogin, menuBarOnly, soundOnClick, bindings, skin, active, steps, list, device, level, interfaceMode
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .status(let s):
            try c.encode("status", forKey: .type)
            try c.encode(s, forKey: .value)

        case .permissions(let acc, let input):
            try c.encode("permissions", forKey: .type)
            try c.encode(acc, forKey: .accessibility)
            try c.encode(input, forKey: .inputMonitoring)

        case .positionPicked(let x, let y):
            try c.encode("positionPicked", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)

        case .error(let message):
            try c.encode("error", forKey: .type)
            try c.encode(message, forKey: .message)

        case .config(let mode, let config):
            try c.encode("config", forKey: .type)
            try c.encode(mode, forKey: .mode)
            switch config {
            case .clicker(let clickerConfig):   try c.encode(clickerConfig, forKey: .config)
            case .jiggler(let jigglerConfig):   try c.encode(jigglerConfig, forKey: .config)
            case .wakeLock(let wl):             try c.encode(wl, forKey: .config)
            case .antiAFK(let a):               try c.encode(a, forKey: .config)
            case .recorder(let r):              try c.encode(r, forKey: .config)
            case .macro(let m):                 try c.encode(m, forKey: .config)
            case .keyboard(let k):              try c.encode(k, forKey: .config)
            }

        case .prefs(let launch, let menuBar, let sound, let skin, let device, let interfaceMode):
            try c.encode("prefs", forKey: .type)
            try c.encode(launch, forKey: .launchAtLogin)
            try c.encode(menuBar, forKey: .menuBarOnly)
            try c.encode(sound, forKey: .soundOnClick)
            try c.encode(skin, forKey: .skin)
            try c.encode(device, forKey: .device)
            try c.encode(interfaceMode, forKey: .interfaceMode)

        case .hotkeys(let bindings):
            try c.encode("hotkeys", forKey: .type)
            try c.encode(bindings, forKey: .bindings)

        case .recording(let active, let steps):
            try c.encode("recording", forKey: .type)
            try c.encode(active, forKey: .active)
            try c.encode(steps, forKey: .steps)

        case .macros(let list):
            try c.encode("macros", forKey: .type)
            try c.encode(list, forKey: .list)

        case .profiles(let list):
            try c.encode("profiles", forKey: .type)
            try c.encode(list, forKey: .list)

        case .log(let message, let level):
            try c.encode("log", forKey: .type)
            try c.encode(message, forKey: .message)
            try c.encode(level, forKey: .level)
        }
    }
}

// MARK: - Lenient decoders for persisted config structs
// Each custom init(from:) is in an extension so the compiler-synthesized
// memberwise initializer is preserved (used extensively throughout the codebase).
// Encoding remains synthesized. Only Decodable is overridden here.

extension ClickerConfig {
    private enum CodingKeys: String, CodingKey { case intervalMs, button, clickType, `repeat`, times, position, x, y, rate, rateUnit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intervalMs = try c.decodeIfPresent(Int.self,          forKey: .intervalMs) ?? 100
        button     = try c.decodeIfPresent(MouseButton.self,  forKey: .button)     ?? .left
        clickType  = try c.decodeIfPresent(ClickType.self,    forKey: .clickType)  ?? .single
        `repeat`   = try c.decodeIfPresent(RepeatMode.self,   forKey: .repeat)     ?? .until
        times      = try c.decodeIfPresent(Int.self,          forKey: .times)      ?? 50
        position   = try c.decodeIfPresent(PositionMode.self, forKey: .position)   ?? .current
        x          = try c.decodeIfPresent(Int.self,          forKey: .x)          ?? 640
        y          = try c.decodeIfPresent(Int.self,          forKey: .y)          ?? 480
        rate       = try c.decodeIfPresent(Int.self,          forKey: .rate)       ?? 5
        rateUnit   = try c.decodeIfPresent(String.self,       forKey: .rateUnit)   ?? "minute"
    }
}

extension JigglerConfig {
    private enum CodingKeys: String, CodingKey { case intervalSec, distancePx, mode, keepAwake, idleOnly }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intervalSec = try c.decodeIfPresent(Int.self,        forKey: .intervalSec) ?? 30
        distancePx  = try c.decodeIfPresent(Int.self,        forKey: .distancePx)  ?? 40
        mode        = try c.decodeIfPresent(JiggleStyle.self, forKey: .mode)        ?? .zen
        keepAwake   = try c.decodeIfPresent(Bool.self,        forKey: .keepAwake)   ?? true
        idleOnly    = try c.decodeIfPresent(Bool.self,        forKey: .idleOnly)    ?? true
    }
}

extension WakeLockConfig {
    private enum CodingKeys: String, CodingKey { case keepDisplayAwake, keepSystemAwake }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepDisplayAwake = try c.decodeIfPresent(Bool.self, forKey: .keepDisplayAwake) ?? true
        keepSystemAwake  = try c.decodeIfPresent(Bool.self, forKey: .keepSystemAwake)  ?? false
    }
}

extension AntiAFKConfig {
    private enum CodingKeys: String, CodingKey { case intervalSec, distancePx, keepAwake }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intervalSec = try c.decodeIfPresent(Int.self,  forKey: .intervalSec) ?? 60
        distancePx  = try c.decodeIfPresent(Int.self,  forKey: .distancePx)  ?? 30
        keepAwake   = try c.decodeIfPresent(Bool.self, forKey: .keepAwake)   ?? true
    }
}

extension KeyboardConfig {
    private enum CodingKeys: String, CodingKey { case combo, intervalMs, `repeat`, times }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        combo      = try c.decodeIfPresent(String.self,     forKey: .combo)      ?? "Space"
        intervalMs = try c.decodeIfPresent(Int.self,        forKey: .intervalMs) ?? 1000
        `repeat`   = try c.decodeIfPresent(RepeatMode.self, forKey: .repeat)     ?? .until
        times      = try c.decodeIfPresent(Int.self,        forKey: .times)      ?? 50
    }
}

// MARK: - Bridge glue

/// Helpers for moving Commands and Events across the WKWebView boundary.
enum Bridge {
    /// Name registered with `WKUserContentController.add(_:name:)`, so JS calls
    /// `window.webkit.messageHandlers.fiddle.postMessage(...)`.
    static let handlerName = "fiddle"

    /// Global JS function the web UI defines to receive Events.
    static let eventFunction = "window.fiddleEvent"

    /// Decode a Command from a `WKScriptMessage.body` (typically `[String: Any]`).
    static func decodeCommand(from body: Any) throws -> Command {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try JSONDecoder().decode(Command.self, from: data)
    }

    /// Build the JS call string for an Event. Pass the result straight to
    /// `webView.evaluateJavaScript(_:)` on the main actor.
    static func script(for event: Event) throws -> String {
        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        return "\(eventFunction)(\(json))"
    }
}
