//
//  KeyEngine.swift
//  Fiddle
//
//  Synthesizes a single key (with optional modifiers) on a precise interval,
//  the keyboard analog of ClickEngine. The timing loop runs on a high-priority
//  queue via a zero-leeway DispatchSourceTimer; only completion marshals to the
//  main actor. The engine takes an already-resolved key code + flags so it stays
//  free of the combo-parsing dependency.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Pure logic (unit tested)

struct KeyRunState {
    let `repeat`: RepeatMode
    let times: Int
    private(set) var count = 0

    init(repeat r: RepeatMode, times: Int) {
        self.`repeat` = r
        self.times = times
    }

    /// Record one press. Returns true if the run should continue.
    mutating func recordPress() -> Bool {
        count += 1
        guard `repeat` == .times else { return true }
        return count < times
    }
}

enum KeyboardSynthesis {
    static func flags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option)  { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }
}

// MARK: - Posting seam

protocol KeyEventPosting {
    func postKey(keyCode: CGKeyCode, flags: CGEventFlags)
}

struct CGKeyEventPoster: KeyEventPosting {
    private let source = CGEventSource(stateID: .combinedSessionState)

    func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = self.source
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Engine

final class KeyEngine {
    private let poster: KeyEventPosting
    private let queue = DispatchQueue(label: "edu.umontana.fiddle.keyengine", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var runState: KeyRunState?
    private var running = false
    private var keyCode: CGKeyCode = 0
    private var flags: CGEventFlags = []

    var onFinished: (@MainActor () -> Void)?

    /// Whether a run is active right now. Lets a completion handler detect that
    /// its notification is stale (a new run started before it was delivered).
    var isRunning: Bool {
        queue.sync { running }
    }

    init(poster: KeyEventPosting = CGKeyEventPoster()) {
        self.poster = poster
    }

    func start(keyCode: CGKeyCode, flags: CGEventFlags, intervalMs: Int, repeat r: RepeatMode, times: Int) {
        stop()
        let interval = max(1, intervalMs)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(interval),
                       repeating: .milliseconds(interval),
                       leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in self?.fire() }
        queue.sync {
            self.keyCode = keyCode
            self.flags = flags
            self.runState = KeyRunState(repeat: r, times: times)
            self.running = true
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            self.timer?.cancel()
            self.timer = nil
            self.running = false
            self.runState = nil
        }
    }

    /// Runs on `queue`.
    private func fire() {
        guard running, var state = runState else { return }
        poster.postKey(keyCode: keyCode, flags: flags)
        let shouldContinue = state.recordPress()
        runState = state
        guard !shouldContinue else { return }
        timer?.cancel()
        timer = nil
        running = false
        runState = nil
        if let onFinished {
            Task { @MainActor in onFinished() }
        }
    }
}
