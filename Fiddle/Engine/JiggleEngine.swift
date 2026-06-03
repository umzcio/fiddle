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
}

// MARK: - Cursor seam

protocol CursorMoving {
    func location() -> CGPoint
    func move(to point: CGPoint)
}

struct CGCursorMover: CursorMoving {
    func location() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func move(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // Re-associate so the next physical mouse move is not snapped back.
        CGAssociateMouseAndMouseCursorPosition(1)
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

    init(mover: CursorMoving = CGCursorMover()) {
        self.mover = mover
    }

    func start(config: JigglerConfig) {
        stop()
        let interval = max(1, config.intervalSec)
        queue.sync {
            self.config = config
            self.direction = 1
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
        let idle = IdleMonitor.secondsSinceLastInput()
        guard JiggleMath.shouldJiggle(idleOnly: config.idleOnly, secondsSinceInput: idle, threshold: idleThreshold) else { return }

        let origin = mover.location()
        let dx = direction * config.distancePx
        let (move, restore) = JiggleMath.nudge(from: origin, dx: dx, zen: config.mode == .zen)
        mover.move(to: move)

        if let restore {
            queue.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
                guard let self, self.config != nil else { return }
                self.mover.move(to: restore)
            }
        } else {
            direction *= -1   // visible: bounce so the cursor stays in place over time
        }
    }
}
