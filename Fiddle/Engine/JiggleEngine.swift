//
//  JiggleEngine.swift
//  Fiddle
//
//  Nudges the cursor on an interval to keep the Mac awake. Zen mode returns the
//  cursor so it does not visibly drift; visible mode alternates direction so the
//  pointer does not walk off screen over time. Idle-only mode pauses while the
//  user is actively working, and keep-awake holds an IOKit power assertion.
//

import CoreGraphics
import Foundation

// MARK: - Pure logic (unit tested)

enum JiggleMath {
    /// Whether to jiggle this tick. In idle-only mode, jiggle only once the user
    /// has been idle for at least `threshold` seconds.
    static func shouldJiggle(idleOnly: Bool, secondsSinceInput: TimeInterval, threshold: TimeInterval) -> Bool {
        guard idleOnly else { return true }
        return secondsSinceInput >= threshold
    }

    /// The point to move to and, for zen mode, the point to return to afterwards.
    static func nudge(from origin: CGPoint, dx: Int, zen: Bool) -> (move: CGPoint, restore: CGPoint?) {
        let move = CGPoint(x: origin.x + CGFloat(dx), y: origin.y)
        return (move, zen ? origin : nil)
    }

    /// Whether the most recent input event was real user activity rather than
    /// this engine's own posted nudge. Our nudges reset the system idle clock,
    /// so the reading roughly equals the time since our last synthetic move
    /// when nothing else happened; a genuinely newer user event reads lower.
    static func isRealUserInput(systemIdle: TimeInterval, sinceLastSynthetic: TimeInterval, tolerance: TimeInterval = 0.5) -> Bool {
        systemIdle < sinceLastSynthetic - tolerance
    }
}

// MARK: - Cursor seam

protocol CursorMoving {
    func location() -> CGPoint
    func move(to point: CGPoint)
}

struct CGCursorMover: CursorMoving {
    private let source = CGEventSource(stateID: .combinedSessionState)

    func location() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func move(to point: CGPoint) {
        // Post a real mouse-moved event instead of CGWarpMouseCursorPosition:
        // a warp generates no events, so it neither resets the system idle
        // timer (the jiggler's whole purpose with keepAwake off) nor looks
        // like input to apps that watch events. Tagged so fiddle's own taps
        // can ignore it.
        if let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvents.userDataTag)
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Engine

final class JiggleEngine {
    private let mover: CursorMoving
    private let power = PowerAssertion()
    private let queue = DispatchQueue(label: "edu.umontana.fiddle.jiggleengine", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var config: JigglerConfig?
    private var direction = 1
    private let idleThreshold: TimeInterval = 3
    // Idle-only bookkeeping (accessed on `queue`). Our nudges are real posted
    // events now, so they reset the system idle clock; these track when the
    // user genuinely last acted versus when we last moved the cursor.
    private var lastSyntheticUptime: TimeInterval = 0
    private var lastUserActivityUptime: TimeInterval = 0
    /// Run identity (accessed on `queue`): a zen restore queued by one run
    /// must not fire into a run that replaced it within the 40ms window.
    private var runGeneration: UInt64 = 0

    init(mover: CursorMoving = CGCursorMover()) {
        self.mover = mover
    }

    func start(config: JigglerConfig) {
        stop()
        let interval = max(1, config.intervalSec)
        queue.sync {
            self.config = config
            self.direction = 1
            self.lastSyntheticUptime = 0
            self.lastUserActivityUptime = ProcessInfo.processInfo.systemUptime - IdleMonitor.secondsSinceLastInput()
            self.runGeneration &+= 1
        }
        if config.keepAwake { power.acquire() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(interval),
                       repeating: .seconds(interval),
                       leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.fire() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync { self.config = nil }
        power.release()
    }

    /// Runs on `queue`.
    private func fire() {
        guard let config else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let systemIdle = IdleMonitor.secondsSinceLastInput()
        // Only count input newer than our own last nudge as user activity, so
        // posting real move events does not make idle-only self-defeating.
        if lastSyntheticUptime == 0 || JiggleMath.isRealUserInput(systemIdle: systemIdle, sinceLastSynthetic: now - lastSyntheticUptime) {
            lastUserActivityUptime = now - systemIdle
        }
        let userIdle = now - lastUserActivityUptime
        guard JiggleMath.shouldJiggle(idleOnly: config.idleOnly, secondsSinceInput: userIdle, threshold: idleThreshold) else { return }

        let origin = mover.location()
        let dx = direction * config.distancePx
        let (move, restore) = JiggleMath.nudge(from: origin, dx: dx, zen: config.mode == .zen)
        mover.move(to: move)
        lastSyntheticUptime = ProcessInfo.processInfo.systemUptime

        if let restore {
            let myGeneration = runGeneration
            queue.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
                guard let self, self.config != nil, self.runGeneration == myGeneration else { return }
                // Only warp back if the cursor is still where we nudged it; if
                // the user started moving, restoring would yank the pointer
                // out from under them.
                let current = self.mover.location()
                guard abs(current.x - move.x) < 2, abs(current.y - move.y) < 2 else { return }
                self.mover.move(to: restore)
                self.lastSyntheticUptime = ProcessInfo.processInfo.systemUptime
            }
        } else {
            direction *= -1   // visible: bounce so the cursor stays in place over time
        }
    }
}
