//
//  HotkeyCombo.swift
//  Fiddle
//
//  Bidirectional mapping between the web UI's combo token strings and
//  KeyboardShortcuts.Shortcut. Token format: zero or more modifier tokens
//  ("ctrl", "opt", "shift", "cmd") followed by exactly one key token (a JS
//  KeyboardEvent.code such as "KeyP", "F6", "Escape", "Digit1"), joined with
//  "+". Example: "ctrl+opt+KeyP". Modifier order does not matter when parsing;
//  string(from:) always emits the canonical order ctrl, opt, shift, cmd.
//

import AppKit
import KeyboardShortcuts

enum HotkeyCombo {
    /// JS KeyboardEvent.code -> KeyboardShortcuts.Key. Single source of truth;
    /// the reverse lookup is derived from this table.
    static let codeToKey: [String: KeyboardShortcuts.Key] = [
        "KeyA": .a, "KeyB": .b, "KeyC": .c, "KeyD": .d, "KeyE": .e, "KeyF": .f,
        "KeyG": .g, "KeyH": .h, "KeyI": .i, "KeyJ": .j, "KeyK": .k, "KeyL": .l,
        "KeyM": .m, "KeyN": .n, "KeyO": .o, "KeyP": .p, "KeyQ": .q, "KeyR": .r,
        "KeyS": .s, "KeyT": .t, "KeyU": .u, "KeyV": .v, "KeyW": .w, "KeyX": .x,
        "KeyY": .y, "KeyZ": .z,
        "Digit0": .zero, "Digit1": .one, "Digit2": .two, "Digit3": .three,
        "Digit4": .four, "Digit5": .five, "Digit6": .six, "Digit7": .seven,
        "Digit8": .eight, "Digit9": .nine,
        "F1": .f1, "F2": .f2, "F3": .f3, "F4": .f4, "F5": .f5, "F6": .f6,
        "F7": .f7, "F8": .f8, "F9": .f9, "F10": .f10, "F11": .f11, "F12": .f12,
        "Escape": .escape, "Space": .space, "Tab": .tab, "Backspace": .delete,
        "ArrowUp": .upArrow, "ArrowDown": .downArrow,
        "ArrowLeft": .leftArrow, "ArrowRight": .rightArrow,
        "Minus": .minus, "Equal": .equal,
        "BracketLeft": .leftBracket, "BracketRight": .rightBracket,
        "Backslash": .backslash, "Semicolon": .semicolon, "Quote": .quote,
        "Comma": .comma, "Period": .period, "Slash": .slash, "Backquote": .backtick,
    ]

    /// Carbon virtual keycode -> JS code token, derived from `codeToKey`.
    static let carbonToCode: [Int: String] = {
        var map: [Int: String] = [:]
        for (code, key) in codeToKey { map[key.rawValue] = code }
        return map
    }()

    /// Modifier tokens in canonical emit order.
    private static let modifierOrder: [(token: String, flag: NSEvent.ModifierFlags)] = [
        ("ctrl", .control), ("opt", .option), ("shift", .shift), ("cmd", .command),
    ]

    /// Parse a combo token string into a Shortcut. Returns nil when the string
    /// has no recognized key token or contains an unknown token.
    static func parse(_ combo: String) -> KeyboardShortcuts.Shortcut? {
        let tokens = combo.split(separator: "+").map(String.init)
        guard !tokens.isEmpty else { return nil }
        var flags: NSEvent.ModifierFlags = []
        var key: KeyboardShortcuts.Key?
        for token in tokens {
            if let mod = modifierOrder.first(where: { $0.token == token }) {
                flags.insert(mod.flag)
            } else if let mapped = codeToKey[token] {
                key = mapped
            } else {
                return nil
            }
        }
        guard let key else { return nil }
        return KeyboardShortcuts.Shortcut(key, modifiers: flags)
    }

    /// Whether a shortcut is safe to register as a system-wide hotkey. A bare
    /// letter, digit, or punctuation key would be swallowed in every app, so
    /// modifier-less bindings are allowed only for function keys and Escape.
    /// (The keyboard auto-presser deliberately bypasses this; it parses combos
    /// to press, not to register.)
    static func isAcceptableGlobalHotkey(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        let mods: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        if !shortcut.modifiers.intersection(mods).isEmpty { return true }
        guard let code = carbonToCode[shortcut.carbonKeyCode] else { return false }
        if code == "Escape" { return true }
        return code.hasPrefix("F") && Int(code.dropFirst()) != nil
    }

    /// Render a Shortcut back to its canonical token string. Returns nil if the
    /// key code is not in our table.
    static func string(from shortcut: KeyboardShortcuts.Shortcut) -> String? {
        guard let code = carbonToCode[shortcut.carbonKeyCode] else { return nil }
        var parts: [String] = []
        for mod in modifierOrder where shortcut.modifiers.contains(mod.flag) {
            parts.append(mod.token)
        }
        parts.append(code)
        return parts.joined(separator: "+")
    }
}
