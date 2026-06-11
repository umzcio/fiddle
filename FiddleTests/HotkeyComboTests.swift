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
    }

    func testGlobalHotkeyAllowsFunctionKeysEscapeAndModifiedKeys() {
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.f6)))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.f12)))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.escape)))
        XCTAssertTrue(HotkeyCombo.isAcceptableGlobalHotkey(KeyboardShortcuts.Shortcut(.a, modifiers: [.command])))
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
