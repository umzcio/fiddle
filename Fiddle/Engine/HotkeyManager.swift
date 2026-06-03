//
//  HotkeyManager.swift
//  Fiddle
//
//  Global shortcuts via the KeyboardShortcuts package. Defaults mirror the
//  mockup: Start/Stop = F6, Toggle jiggler = F7, Pick position = Ctrl+Opt+P,
//  Panic = Command+Escape. The panic key force-stops every engine and works even
//  when Fiddle is not focused. Bindings persist in UserDefaults via the package.
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let startStop = Self("startStop", default: .init(.f6))
    static let toggleJiggler = Self("toggleJiggler", default: .init(.f7))
    static let pickPosition = Self("pickPosition", default: .init(.p, modifiers: [.control, .option]))
    static let panic = Self("panic", default: .init(.escape, modifiers: [.command]))
}

@MainActor
final class HotkeyManager {
    var onStartStop: (() -> Void)?
    var onToggleJiggler: (() -> Void)?
    var onPickPosition: (() -> Void)?
    var onPanic: (() -> Void)?

    func register() {
        KeyboardShortcuts.onKeyDown(for: .startStop) { [weak self] in self?.onStartStop?() }
        KeyboardShortcuts.onKeyDown(for: .toggleJiggler) { [weak self] in self?.onToggleJiggler?() }
        KeyboardShortcuts.onKeyDown(for: .pickPosition) { [weak self] in self?.onPickPosition?() }
        KeyboardShortcuts.onKeyDown(for: .panic) { [weak self] in self?.onPanic?() }
    }

    /// The package shortcut name backing a given action.
    func name(for action: HotkeyAction) -> KeyboardShortcuts.Name {
        switch action {
        case .startStop:     return .startStop
        case .toggleJiggler: return .toggleJiggler
        case .pickPosition:  return .pickPosition
        case .panic:         return .panic
        }
    }

    /// Rebind an action. The package persists this and updates the live binding
    /// for the handler already registered in `register()`.
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut, for action: HotkeyAction) {
        KeyboardShortcuts.setShortcut(shortcut, for: name(for: action))
    }

    /// The currently bound shortcut for an action, if any.
    func shortcut(for action: HotkeyAction) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name(for: action))
    }
}
