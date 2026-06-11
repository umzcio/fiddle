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
    func post(button: MouseButton, down: Bool, at point: CGPoint, clickState: Int)
    func move(to point: CGPoint)
}

struct CGSingleEventPoster: SingleMouseEventPosting {
    private let source = CGEventSource(stateID: .combinedSessionState)

    func post(button: MouseButton, down: Bool, at point: CGPoint, clickState: Int) {
        let source = self.source
        let cgButton = ClickMapping.cgButton(button)
        let type = down ? ClickMapping.downType(button) : ClickMapping.upType(button)
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: cgButton) {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, clickState)))
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvents.userDataTag)
            event.post(tap: .cghidEventTap)
        }
    }

    func move(to point: CGPoint) {
        let source = self.source
        if let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvents.userDataTag)
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Engine

final class PlaybackEngine {
    private let poster: SingleMouseEventPosting
    private let lock = NSLock()
    private var events: [RecordedEvent] = []
    private var runState: PlaybackRunState?
    private var running = false
    /// Run identity. Bumped on every start; a worker only acts while its own
    /// generation is current, so a stale worker can neither keep playing after
    /// a restart nor tear down the run that replaced it.
    private var generation: UInt64 = 0

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
        self.generation &+= 1
        let myGeneration = generation
        lock.unlock()

        let worker = Thread { [weak self] in self?.playLoop(myGeneration: myGeneration) }
        worker.qualityOfService = .userInitiated
        worker.start()
    }

    func stop() {
        lock.lock()
        running = false
        runState = nil
        lock.unlock()
    }

    private func isRunning(_ myGeneration: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running && generation == myGeneration
    }

    private func playLoop(myGeneration: UInt64) {
        var completed = false
        // Downs posted without their matching up yet. Released on every exit,
        // so a stop or panic mid-pair cannot leave a button logically pressed.
        var pressed: [MouseButton: (point: CGPoint, clickState: Int)] = [:]
        defer {
            for (button, held) in pressed {
                poster.post(button: button, down: false, at: held.point, clickState: held.clickState)
            }
        }
        while isRunning(myGeneration) {
            let snapshot: [RecordedEvent] = { lock.lock(); defer { lock.unlock() }; return events }()
            for event in snapshot {
                if event.delayMs > 0 {
                    var remaining = event.delayMs
                    while remaining > 0 {
                        if !isRunning(myGeneration) { return }
                        let slice = min(remaining, 25)
                        Thread.sleep(forTimeInterval: Double(slice) / 1000.0)
                        remaining -= slice
                    }
                }
                if !isRunning(myGeneration) { return }   // external stop: no onFinished
                let point = CGPoint(x: event.x, y: event.y)
                if event.kind == .move {
                    poster.move(to: point)
                } else {
                    let down = event.kind == .down
                    poster.post(button: event.button, down: down, at: point, clickState: event.clickState)
                    if down {
                        pressed[event.button] = (point, event.clickState)
                    } else {
                        pressed.removeValue(forKey: event.button)
                    }
                }
            }
            lock.lock()
            let stale = !(running && generation == myGeneration)
            var again = false
            if !stale, var state = runState {
                again = state.finishPass()
                runState = state
            }
            lock.unlock()
            if stale { return }   // a newer run owns the engine now
            if !again { completed = true; break }
        }
        lock.lock()
        // Only tear down state that still belongs to this run.
        if generation == myGeneration {
            running = false
            runState = nil
        }
        let notify = completed && generation == myGeneration
        lock.unlock()
        if notify, let onFinished { Task { @MainActor in onFinished() } }
    }
}
