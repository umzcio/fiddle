//
//  LoginItem.swift
//  Fiddle
//
//  Registers / unregisters fiddle as a macOS login item via SMAppService.
//

import ServiceManagement
import os

enum LoginItem {
    private static let log = Logger(subsystem: "app.fiddle.Fiddle", category: "loginitem")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            log.error("login item \(enabled ? "register" : "unregister") failed: \(String(describing: error), privacy: .public)")
        }
    }
}
