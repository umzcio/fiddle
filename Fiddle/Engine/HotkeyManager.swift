//
//  HotkeyManager.swift
//  Fiddle
//
//  Global shortcuts via the KeyboardShortcuts package. Defaults mirror the
//  mockup: Start/Stop = F6, Toggle jiggler = F7, Pick position = Ctrl+Opt+P,
//  Panic = Command+Escape. The panic key force-stops every engine and works even
//  when Fiddle is not focused. Bindings persist in UserDefaults via the package;
//  a sealed copy kept by SettingsStore lets launch undo changes made outside.
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
    /// Actions whose stored binding was put back by `register(trusted:)`
    /// (changed outside fiddle, or not safe as a system-wide hotkey), so the
    /// controller can tell the user.
    private(set) var resetActions: [HotkeyAction] = []
    func acknowledgeResets() { resetActions = [] }

    /// The binding an action must have at launch. The package registers
    /// whatever UserDefaults holds, and another process can write it, so the
    /// stored value is checked against `trusted`, the sealed copy of what
    /// fiddle last set. With no trusted copy, or a trusted binding that is no
    /// longer acceptable, the action expects its default.
    nonisolated static func expectedBinding(for action: HotkeyAction, trusted: [String: String]?) -> KeyboardShortcuts.Shortcut? {
        let fallback = name(for: action).defaultShortcut
        guard let token = trusted?[action.rawValue],
              let shortcut = HotkeyCombo.parse(token),
              HotkeyCombo.isAcceptableGlobalHotkey(shortcut) else { return fallback }
        return shortcut
    }

    /// Actions whose current binding differs from the expected one.
    nonisolated static func actionsToReset(current: (HotkeyAction) -> KeyboardShortcuts.Shortcut?, trusted: [String: String]?) -> [HotkeyAction] {
        HotkeyAction.allCases.filter { current($0) != expectedBinding(for: $0, trusted: trusted) }
    }

    func register(trusted: [String: String]?) {
        resetActions = Self.actionsToReset(current: { shortcut(for: $0) }, trusted: trusted)
        for action in resetActions {
            KeyboardShortcuts.setShortcut(Self.expectedBinding(for: action, trusted: trusted), for: Self.name(for: action))
        }
        KeyboardShortcuts.onKeyDown(for: .startStop) { [weak self] in self?.onStartStop?() }
        KeyboardShortcuts.onKeyDown(for: .toggleJiggler) { [weak self] in self?.onToggleJiggler?() }
        KeyboardShortcuts.onKeyDown(for: .pickPosition) { [weak self] in self?.onPickPosition?() }
        KeyboardShortcuts.onKeyDown(for: .panic) { [weak self] in self?.onPanic?() }
    }

    /// The package shortcut name backing a given action.
    nonisolated static func name(for action: HotkeyAction) -> KeyboardShortcuts.Name {
        switch action {
        case .startStop:     return .startStop
        case .toggleJiggler: return .toggleJiggler
        case .pickPosition:  return .pickPosition
        case .panic:         return .panic
        }
    }

    /// Every bound action as a combo token keyed by action raw value: the
    /// shape the web keycaps and the sealed copy both use.
    func currentTokens() -> [String: String] {
        var out: [String: String] = [:]
        for action in HotkeyAction.allCases {
            if let shortcut = shortcut(for: action), let token = HotkeyCombo.string(from: shortcut) {
                out[action.rawValue] = token
            }
        }
        return out
    }

    /// Rebind an action. The package persists this and updates the live binding
    /// for the handler already registered in `register()`.
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut, for action: HotkeyAction) {
        KeyboardShortcuts.setShortcut(shortcut, for: Self.name(for: action))
    }

    /// The currently bound shortcut for an action, if any.
    func shortcut(for action: HotkeyAction) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: Self.name(for: action))
    }

    /// Restore every binding to the defaults declared above.
    func resetToDefaults() {
        KeyboardShortcuts.reset(.startStop, .toggleJiggler, .pickPosition, .panic)
    }
}
