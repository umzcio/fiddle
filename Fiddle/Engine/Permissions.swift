//
//  Permissions.swift
//  Fiddle
//
//  Accessibility is required to synthesize mouse events; nothing in the engine
//  works without it. Input Monitoring is only needed by the Phase 2 recorder
//  but is reported here so the UI can show a complete picture.
//

import AppKit
import ApplicationServices
import IOKit.hid

@MainActor
final class PermissionsManager {

    /// Whether the process is trusted for the Accessibility API.
    /// - Parameter promptIfNeeded: when true, macOS shows its "open System
    ///   Settings" prompt if trust is missing. Pass false for silent polling.
    func accessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Whether Input Monitoring access has been granted (listen-event access).
    func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Prompt for Input Monitoring access (needed to record input). Returns the
    /// resulting grant state; the change may require an app relaunch to take hold.
    @discardableResult
    func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
