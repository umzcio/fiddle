//
//  Profile.swift
//  Fiddle
//
//  A named snapshot of the full automation setup (every engine config plus the
//  Mouse/Keyboard device), so the user can switch between configurations. App
//  wide preferences (skin, launch at login, sound) are deliberately not captured.
//

import Foundation

struct Profile: Codable, Equatable {
    var id: String
    var name: String
    var clicker: ClickerConfig
    var jiggler: JigglerConfig
    var wakeLock: WakeLockConfig
    var antiAFK: AntiAFKConfig
    var keyboard: KeyboardConfig
    var device: String
}

// MARK: - Lenient decoder

extension Profile {
    private enum CodingKeys: String, CodingKey { case id, name, clicker, jiggler, wakeLock, antiAFK, keyboard, device }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(String.self,        forKey: .id)       ?? ""
        name     = try c.decodeIfPresent(String.self,        forKey: .name)     ?? ""
        clicker  = try c.decodeIfPresent(ClickerConfig.self, forKey: .clicker)  ?? ClickerConfig(intervalMs: 100, button: .left, clickType: .single, repeat: .until, times: 50, position: .current, x: 640, y: 480)
        jiggler  = try c.decodeIfPresent(JigglerConfig.self, forKey: .jiggler)  ?? JigglerConfig(intervalSec: 30, distancePx: 40, mode: .zen, keepAwake: true, idleOnly: true)
        wakeLock = try c.decodeIfPresent(WakeLockConfig.self, forKey: .wakeLock) ?? WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: false)
        antiAFK  = try c.decodeIfPresent(AntiAFKConfig.self,  forKey: .antiAFK)  ?? AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true)
        keyboard = try c.decodeIfPresent(KeyboardConfig.self, forKey: .keyboard) ?? KeyboardConfig(combo: "Space", intervalMs: 1000, repeat: .until, times: 50)
        device   = try c.decodeIfPresent(String.self,         forKey: .device)   ?? "mouse"
    }
}
