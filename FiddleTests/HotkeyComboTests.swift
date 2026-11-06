//
//  HotkeyComboTests.swift
//  FiddleTests
//
//  Round-trip tests for the combo-token <-> KeyboardShortcuts.Shortcut mapping.
//

import XCTest
import KeyboardShortcuts
@testable import Fiddle

final class HotkeyComboTests: XCTestCase {
    func testParsePlainFunctionKey() {
        let s = HotkeyCombo.parse("F6")
        XCTAssertEqual(s, KeyboardShortcuts.Shortcut(.f6))
    }

    func testParseWithModifiers() {
        let s = HotkeyCombo.parse("ctrl+opt+KeyP")
        XCTAssertEqual(s, KeyboardShortcuts.Shortcut(.p, modifiers: [.control, .option]))
    }

    func testParseCommandEscape() {
        let s = HotkeyCombo.parse("cmd+Escape")
        XCTAssertEqual(s, KeyboardShortcuts.Shortcut(.escape, modifiers: [.command]))
    }

    func testParseDigit() {
        XCTAssertEqual(HotkeyCombo.parse("Digit1"), KeyboardShortcuts.Shortcut(.one))
    }

    func testParseModifierOrderIsIrrelevant() {
        XCTAssertEqual(HotkeyCombo.parse("cmd+ctrl+KeyK"),
                       HotkeyCombo.parse("ctrl+cmd+KeyK"))
    }

    func testParseRejectsModifierOnly() {
        XCTAssertNil(HotkeyCombo.parse("cmd+shift"))
    }

    func testParseRejectsUnknownToken() {
        XCTAssertNil(HotkeyCombo.parse("Banana"))
    }

    func testParseRejectsEmpty() {
        XCTAssertNil(HotkeyCombo.parse(""))
    }

    func testGlobalHotkeyRejectsBareKeys() {
        XCTAssertFalse(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.a)))
        XCTAssertFalse(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.one)))
        XCTAssertFalse(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.space)))
        XCTAssertFalse(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.escape)))
    }

    // Shift alone is ordinary typing: Shift+A is just a capital A.
    func testGlobalHotkeyRejectsShiftOnly() {
        XCTAssertFalse(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.a, modifiers: [.shift])))
        XCTAssertFalse(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.escape, modifiers: [.shift])))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.f6, modifiers: [.shift])))
    }

    func testGlobalHotkeyAllowsFunctionKeysAndModifiedKeys() {
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.f6)))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.f12)))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.a, modifiers: [.command])))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.a, modifiers: [.option, .shift])))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.escape, modifiers: [.command])))
    }

    func testStringFromShortcutCanonicalOrder() {
        let s = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .control])
        XCTAssertEqual(HotkeyCombo.string(from: s), "ctrl+cmd+KeyK")
    }

    func testStringFromPlainKey() {
        XCTAssertEqual(HotkeyCombo.string(from: KeyboardShortcuts.Shortcut(.f7)), "F7")
    }

    func testRoundTrip() {
        for token in ["F6", "F7", "ctrl+opt+KeyP", "cmd+Escape", "shift+KeyA", "Digit9"] {
            guard let shortcut = HotkeyCombo.parse(token) else {
                return XCTFail("failed to parse \(token)")
            }
            XCTAssertEqual(HotkeyCombo.string(from: shortcut), token,
                           "round trip mismatch for \(token)")
        }
    }
}

final class StoredHotkeyTests: XCTestCase {
    private let defaults: [HotkeyAction: KeyboardShortcuts.Shortcut] = [
        .startStop: .init(.f6),
        .toggleJiggler: .init(.f7),
        .pickPosition: .init(.p, modifiers: [.control, .option]),
        .panic: .init(.escape, modifiers: [.command]),
    ]

    // KeyboardShortcuts registers whatever is in UserDefaults at launch, and
    // another process can write it. With no sealed copy, everything must be
    // at its default.
    func testWithoutTrustedCopyEveryChangedBindingIsReset() {
        var stored = defaults
        stored[.startStop] = .init(.a, modifiers: [.command])
        stored[.panic] = nil
        let reset = HotkeyManager.actionsToReset(current: { stored[$0] }, trusted: nil)
        XCTAssertEqual(Set(reset), [.startStop, .panic])
        XCTAssertEqual(HotkeyManager.expectedBinding(for: .startStop, trusted: nil), defaults[.startStop])
    }

    func testBindingsMatchingTheSealedCopyAreKept() {
        var stored = defaults
        stored[.startStop] = .init(.s, modifiers: [.command, .option])
        let trusted = ["startStop": "opt+cmd+KeyS"]
        XCTAssertEqual(HotkeyCombo.string(from: stored[.startStop]!), "opt+cmd+KeyS")
        XCTAssertTrue(HotkeyManager.actionsToReset(current: { stored[$0] }, trusted: trusted).isEmpty)
    }

    // A planted Shift+A differs from the sealed F6, so it goes back to F6.
    func testPlantedBindingIsPutBackToTheSealedOne() {
        var stored = defaults
        stored[.startStop] = .init(.a, modifiers: [.shift])
        let trusted = ["startStop": "ctrl+KeyJ"]
        XCTAssertEqual(HotkeyManager.actionsToReset(current: { stored[$0] }, trusted: trusted), [.startStop])
        XCTAssertEqual(HotkeyManager.expectedBinding(for: .startStop, trusted: trusted), .init(.j, modifiers: [.control]))
    }

    // A sealed binding that the modifier rule now refuses falls back to the default.
    func testRefusedSealedBindingFallsBackToDefault() {
        let trusted = ["startStop": "shift+KeyA", "panic": "Space"]
        XCTAssertEqual(HotkeyManager.expectedBinding(for: .startStop, trusted: trusted), defaults[.startStop])
        XCTAssertEqual(HotkeyManager.expectedBinding(for: .panic, trusted: trusted), defaults[.panic])
    }
}
