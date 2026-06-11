//
//  ClickRecorder.swift
//  Fiddle
//
//  Captures mouse button events via a listen-only CGEvent tap (same approach as
//  PositionPicker). Yields Quartz global coordinates, which match CGEvent click
//  posting. The controller supplies an `exclude` predicate so clicks inside
//  fiddle's own window are dropped (so the user can press Record/Stop without
//  recording it). Timing uses a monotonic clock.
//

import CoreGraphics
import Foundation

/// Marker stamped on every mouse event fiddle synthesizes (clicker, playback),
/// read back by the recorder tap so the app never records its own output.
enum SyntheticEvents {
    static let userDataTag: Int64 = 0xF1DD1E
}

@MainActor
final class ClickRecorder {
    /// Returns true for points that should NOT be recorded (e.g. inside fiddle's
    /// own window). Set by the controller.
    var exclude: ((CGPoint) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var events: [RecordedEvent] = []
    private var lastTimestampNs: UInt64 = 0

    var isRecording: Bool { tap != nil }

    func start() {
        _ = stop()
        events = []
        lastTimestampNs = DispatchTime.now().uptimeNanoseconds

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)  | (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let obj = Unmanaged<ClickRecorder>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = obj.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon else { return Unmanaged.passUnretained(event) }
                // Drop fiddle's own synthesized events; recording them would
                // feed the app's output back in as if it were user input.
                if event.getIntegerValueField(.eventSourceUserData) == SyntheticEvents.userDataTag {
                    return Unmanaged.passUnretained(event)
                }
                let recorder = Unmanaged<ClickRecorder>.fromOpaque(refcon).takeUnretainedValue()
                let location = event.location
                let clickState = Int(event.getIntegerValueField(.mouseEventClickState))
                DispatchQueue.main.async { recorder.capture(type: type, location: location, clickState: clickState) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Stop capturing and return the events recorded since `start()`.
    @discardableResult
    func stop() -> [RecordedEvent] {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
        return events
    }

    private func capture(type: CGEventType, location: CGPoint, clickState: Int) {
        guard isRecording, let mapped = RecordEventMapping.event(for: type) else { return }
        if exclude?(location) == true { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let delayMs = lastTimestampNs == 0 ? 0 : Int((now &- lastTimestampNs) / 1_000_000)
        lastTimestampNs = now
        events.append(RecordedEvent(
            kind: mapped.kind, button: mapped.button,
            x: Int(location.x.rounded()), y: Int(location.y.rounded()),
            delayMs: max(0, delayMs),
            clickState: max(1, clickState)
        ))
    }
}
