//
//  Macro.swift
//  Fiddle
//
//  A macro is a named, ordered list of steps (click / wait / move). It compiles
//  to the same [RecordedEvent] timeline the PlaybackEngine already plays, so the
//  sequencer reuses the recorder's playback path. Pure and unit testable.
//

import Foundation

enum MacroStepKind: String, Codable { case click, wait, move }

struct MacroStep: Codable, Equatable {
    var kind: MacroStepKind
    var button: MouseButton    // click only
    var clickType: ClickType   // click only
    var x: Int                 // click / move
    var y: Int                 // click / move
    var ms: Int                // wait only
}

struct Macro: Codable, Equatable {
    var id: String
    var name: String
    var steps: [MacroStep]
}

// MARK: - Lenient decoders

extension MacroStep {
    private enum CodingKeys: String, CodingKey { case kind, button, clickType, x, y, ms }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind      = try c.decodeIfPresent(MacroStepKind.self, forKey: .kind)      ?? .click
        button    = try c.decodeIfPresent(MouseButton.self,   forKey: .button)    ?? .left
        clickType = try c.decodeIfPresent(ClickType.self,     forKey: .clickType) ?? .single
        x         = try c.decodeIfPresent(Int.self,           forKey: .x)         ?? 0
        y         = try c.decodeIfPresent(Int.self,           forKey: .y)         ?? 0
        ms        = try c.decodeIfPresent(Int.self,           forKey: .ms)        ?? 0
    }
}

extension Macro {
    private enum CodingKeys: String, CodingKey { case id, name, steps }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(String.self,      forKey: .id)    ?? ""
        name  = try c.decodeIfPresent(String.self,      forKey: .name)  ?? ""
        steps = try c.decodeIfPresent([MacroStep].self, forKey: .steps) ?? []
    }
}

/// Playback selector for a saved macro.
struct MacroConfig: Codable, Equatable {
    var macroId: String
    var `repeat`: RepeatMode
    var times: Int
}

enum MacroCompiler {
    /// Compile macro steps into a playback timeline. Wait steps accumulate into
    /// the delay before the next action; clicks emit down/up pairs; moves emit a
    /// single move event.
    static func compile(_ steps: [MacroStep]) -> [RecordedEvent] {
        var out: [RecordedEvent] = []
        var pending = 0
        for step in steps {
            switch step.kind {
            case .wait:
                pending += max(0, step.ms)
            case .move:
                out.append(RecordedEvent(kind: .move, button: .left, x: step.x, y: step.y, delayMs: pending))
                pending = 0
            case .click:
                let pairs = step.clickType == .double ? 2 : 1
                for pair in 0..<pairs {
                    // The second pair of a double click carries clickState 2 on
                    // both events so target apps register a real double-click.
                    out.append(RecordedEvent(kind: .down, button: step.button, x: step.x, y: step.y, delayMs: pair == 0 ? pending : 30, clickState: pair + 1))
                    out.append(RecordedEvent(kind: .up, button: step.button, x: step.x, y: step.y, delayMs: 10, clickState: pair + 1))
                }
                pending = 0
            }
        }
        return out
    }
}
