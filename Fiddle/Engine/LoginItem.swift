//
//  LoginItem.swift
//  Fiddle
//
//  Registers / unregisters fiddle as a macOS login item via SMAppService.
//

import ServiceManagement
import os

enum LoginItem {
    private static let log = Logger(subsystem: "edu.umontana.fiddle", category: "loginitem")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS is waiting for the user to approve the item in System Settings.
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns true when the effective login-item state matches the request.
    /// register() can throw, and it can also land in .requiresApproval without
    /// throwing; both read back as a mismatch the caller must surface.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            log.error("login item \(enabled ? "register" : "unregister") failed: \(String(describing: error), privacy: .public)")
        }
        return isEnabled == enabled
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
