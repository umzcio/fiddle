//
//  PowerAssertion.swift
//  Fiddle
//
//  Thin wrapper over an IOKit power assertion. Always released on stop and on
//  deinit so a missed stop cannot keep the Mac awake forever.
//

import IOKit.pwr_mgt
import os

final class PowerAssertion {
    enum Kind {
        case displaySleep
        case systemSleep
        var ioType: String {
            switch self {
            case .displaySleep: return kIOPMAssertionTypePreventUserIdleDisplaySleep
            case .systemSleep:  return kIOPMAssertionTypePreventUserIdleSystemSleep
            }
        }
    }

    private let kind: Kind
    private var assertionID = IOPMAssertionID(0)
    private var active = false
    private let log = Logger(subsystem: "app.fiddle.Fiddle", category: "power")

    init(kind: Kind = .displaySleep) { self.kind = kind }

    /// Acquire the assertion. Idempotent.
    func acquire(reason: String = "fiddle is keeping your Mac awake") {
        guard !active else { return }
        let result = IOPMAssertionCreateWithName(
            kind.ioType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            active = true
        } else {
            log.error("power assertion failed: \(result)")
        }
    }

    /// Release the assertion if held. Idempotent.
    func release() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        active = false
    }

    deinit { if active { IOPMAssertionRelease(assertionID) } }
}
