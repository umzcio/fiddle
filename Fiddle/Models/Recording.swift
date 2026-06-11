//
//  Recording.swift
//  Fiddle
//
//  The Click Recorder data model and its pure logic: the raw captured events,
//  the playback config carried on the wire, and projections used for display.
//  Kept free of any tap/posting concerns so it is fully unit testable.
//

import CoreGraphics
import Foundation

/// One raw captured mouse event. `delayMs` is the delay before this event since
/// the previous one (the first kept event uses the time since recording started,
/// which also spaces repeated playback loops).
struct RecordedEvent: Codable, Equatable {
    enum Kind: String, Codable { case down, up, move }
    var kind: Kind
    var button: MouseButton
    var x: Int
    var y: Int
    var delayMs: Int
    /// CGEvent click state: 2 on both events of a double-click's second pair
    /// (3 for a triple), 1 otherwise. Target apps read this field to detect
    /// multi-clicks, so playback must reproduce it.
    var clickState: Int = 1
}

// MARK: - Lenient decoder

extension RecordedEvent {
    private enum CodingKeys: String, CodingKey { case kind, button, x, y, delayMs, clickState }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind       = try c.decodeIfPresent(Kind.self,        forKey: .kind)       ?? .down
        button     = try c.decodeIfPresent(MouseButton.self, forKey: .button)     ?? .left
        x          = try c.decodeIfPresent(Int.self,         forKey: .x)          ?? 0
        y          = try c.decodeIfPresent(Int.self,         forKey: .y)          ?? 0
        delayMs    = try c.decodeIfPresent(Int.self,         forKey: .delayMs)    ?? 0
        clickState = try c.decodeIfPresent(Int.self,         forKey: .clickState) ?? 1
    }
}

/// Playback repeat config, mirroring the Auto Clicker's repeat controls.
struct RecorderConfig: Codable, Equatable {
    var `repeat`: RepeatMode
    var times: Int
}

/// A display projection of the sequence for the UI step list.
struct DisplayStep: Codable, Equatable {
    var label: String
    var x: Int
    var y: Int
    var delayMs: Int
}

/// Maps a Core Graphics event type to a recorder button + kind, or nil if the
/// event is not a mouse button event we record.
enum RecordEventMapping {
    static func event(for type: CGEventType) -> (button: MouseButton, kind: RecordedEvent.Kind)? {
        switch type {
        case .leftMouseDown:  return (.left, .down)
        case .leftMouseUp:    return (.left, .up)
        case .rightMouseDown: return (.right, .down)
        case .rightMouseUp:   return (.right, .up)
        case .otherMouseDown: return (.middle, .down)
        case .otherMouseUp:   return (.middle, .up)
        default:              return nil
        }
    }
}

enum RecordedSequence {
    /// Coalesce a down+up of the same button at the same point into one "click"
    /// row; render anything else as a press/release row. A coalesced click shows
    /// the down event's delay.
    static func displaySteps(_ events: [RecordedEvent]) -> [DisplayStep] {
        var steps: [DisplayStep] = []
        var i = 0
        while i < events.count {
            let e = events[i]
            if e.kind == .down, i + 1 < events.count {
                let n = events[i + 1]
                if n.kind == .up, n.button == e.button, n.x == e.x, n.y == e.y {
                    steps.append(DisplayStep(label: "\(name(e.button)) click", x: e.x, y: e.y, delayMs: e.delayMs))
                    i += 2
                    continue
                }
            }
            let verb: String
            switch e.kind {
            case .down: verb = "press"
            case .up:   verb = "release"
            case .move: verb = "move"
            }
            steps.append(DisplayStep(label: "\(name(e.button)) \(verb)", x: e.x, y: e.y, delayMs: e.delayMs))
            i += 1
        }
        return steps
    }

    private static func name(_ button: MouseButton) -> String {
        switch button {
        case .left:   return "Left"
        case .right:  return "Right"
        case .middle: return "Middle"
        }
    }
}
