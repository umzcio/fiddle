//
//  PositionPicker.swift
//  Fiddle
//
//  Captures the location of the next click so the user can pick a fixed target
//  for the auto clicker. Uses a listen-only event tap, which yields Quartz
//  global coordinates (top-left origin) directly, matching CGEvent click posts.
//

import CoreGraphics
import Foundation

@MainActor
final class PositionPicker {
    var onPicked: ((Int, Int) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isPicking: Bool { tap != nil }

    func begin() {
        cancel()
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let obj = Unmanaged<PositionPicker>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = obj.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon else { return Unmanaged.passUnretained(event) }
                // Ignore fiddle's own synthesized clicks: with the clicker
                // running, one of its posts could otherwise satisfy the pick
                // instead of the user's click.
                if event.getIntegerValueField(.eventSourceUserData) == SyntheticEvents.userDataTag {
                    return Unmanaged.passUnretained(event)
                }
                let picker = Unmanaged<PositionPicker>.fromOpaque(refcon).takeUnretainedValue()
                let location = event.location
                DispatchQueue.main.async {
                    picker.finish(x: Int(location.x.rounded()), y: Int(location.y.rounded()))
                }
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

    func cancel() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func finish(x: Int, y: Int) {
        guard isPicking else { return }
        onPicked?(x, y)
        cancel()
    }
}
