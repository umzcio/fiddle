//
//  PlaybackEngine.swift
//  Fiddle
//
//  Replays a recorded sequence of mouse events, honoring each event's delay,
//  with times-or-until repeat. The replay loop runs on a dedicated worker thread
//  and is guarded by a lock; only natural completion marshals onFinished back to
//  the main actor (an external stop does not, so it cannot race a new run).
//

import CoreGraphics
import Foundation

// MARK: - Pure repeat logic (unit tested)

struct PlaybackRunState {
    let config: RecorderConfig
    private(set) var pass = 0
    init(config: RecorderConfig) { self.config = config }

    /// Call after finishing one full pass. Returns true if another pass runs.
    mutating func finishPass() -> Bool {
        pass += 1
        guard config.repeat == .times else { return true }
        return pass < config.times
    }
}

// MARK: - Single-event posting seam

protocol SingleMouseEventPosting {
    func post(button: MouseButton, down: Bool, at point: CGPoint)
    func move(to point: CGPoint)
}

struct CGSingleEventPoster: SingleMouseEventPosting {
    private let source = CGEventSource(stateID: .combinedSessionState)

    func post(button: MouseButton, down: Bool, at point: CGPoint) {
        let source = self.source
        let cgButton = ClickMapping.cgButton(button)
        let type = down ? ClickMapping.downType(button) : ClickMapping.upType(button)
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: cgButton) {
            event.post(tap: .cghidEventTap)
        }
    }

    func move(to point: CGPoint) {
        let source = self.source
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

// MARK: - Engine

final class PlaybackEngine {
    private let poster: SingleMouseEventPosting
    private let lock = NSLock()
    private var events: [RecordedEvent] = []
    private var runState: PlaybackRunState?
    private var running = false

    /// Called on the main actor only when a run completes on its own.
    var onFinished: (@MainActor () -> Void)?

    init(poster: SingleMouseEventPosting = CGSingleEventPoster()) {
        self.poster = poster
    }

    func start(events: [RecordedEvent], config: RecorderConfig) {
        stop()
        guard !events.isEmpty else {
            if let onFinished { Task { @MainActor in onFinished() } }
            return
        }
        lock.lock()
        self.events = events
        self.runState = PlaybackRunState(config: config)
        self.running = true
        lock.unlock()

        let worker = Thread { [weak self] in self?.playLoop() }
        worker.qualityOfService = .userInitiated
        worker.start()
    }

    func stop() {
        lock.lock()
        running = false
        runState = nil
        lock.unlock()
    }

    private func isRunning() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private func playLoop() {
        var completed = false
        // Downs posted without their matching up yet. Released on every exit,
        // so a stop or panic mid-pair cannot leave a button logically pressed.
        var pressed: [MouseButton: CGPoint] = [:]
        defer {
            for (button, point) in pressed {
                poster.post(button: button, down: false, at: point)
            }
        }
        while isRunning() {
            let snapshot: [RecordedEvent] = { lock.lock(); defer { lock.unlock() }; return events }()
            for event in snapshot {
                if event.delayMs > 0 {
                    var remaining = event.delayMs
                    while remaining > 0 {
                        if !isRunning() { return }
                        let slice = min(remaining, 25)
                        Thread.sleep(forTimeInterval: Double(slice) / 1000.0)
                        remaining -= slice
                    }
                }
                if !isRunning() { return }   // external stop: no onFinished
                let point = CGPoint(x: event.x, y: event.y)
                if event.kind == .move {
                    poster.move(to: point)
                } else {
                    let down = event.kind == .down
                    poster.post(button: event.button, down: down, at: point)
                    if down {
                        pressed[event.button] = point
                    } else {
                        pressed.removeValue(forKey: event.button)
                    }
                }
            }
            let again: Bool = {
                lock.lock(); defer { lock.unlock() }
                guard running, var state = runState else { return false }
                let cont = state.finishPass()
                runState = state
                return cont
            }()
            if !again { completed = true; break }
        }
        lock.lock(); running = false; runState = nil; lock.unlock()
        if completed, let onFinished { Task { @MainActor in onFinished() } }
    }
}
