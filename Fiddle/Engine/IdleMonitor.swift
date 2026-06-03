//
//  IdleMonitor.swift
//  Fiddle
//
//  Reports how long the user has been idle, used by the jiggler's idle-only mode
//  to pause while the user is actively working.
//

import CoreGraphics
import Foundation

enum IdleMonitor {
    /// Seconds since the last user input event of any kind.
    static func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType is (~0); CGEventType has no named case for it.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
