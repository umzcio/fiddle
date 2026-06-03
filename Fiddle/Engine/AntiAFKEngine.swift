//
//  AntiAFKEngine.swift
//  Fiddle
//
//  Periodically nudges the cursor so apps and games do not mark the user idle.
//  Alternates direction each tick so the pointer stays in place over time.
//  Optionally holds a keep-awake assertion. A keystroke option arrives in M7.
//

import CoreGraphics
import Foundation

final class AntiAFKEngine {
    private let mover: CursorMoving
    private let power = PowerAssertion(kind: .displaySleep)
    private let queue = DispatchQueue(label: "edu.umontana.fiddle.antiafk", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var config: AntiAFKConfig?
    private var direction = 1

    init(mover: CursorMoving = CGCursorMover()) {
        self.mover = mover
    }

    func start(config: AntiAFKConfig) {
        stop()
        queue.sync {
            self.config = config
            self.direction = 1
        }
        if config.keepAwake { power.acquire(reason: "fiddle Anti-AFK") }
        let interval = max(1, config.intervalSec)
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
        let origin = mover.location()
        let dx = direction * config.distancePx
        let (move, _) = JiggleMath.nudge(from: origin, dx: dx, zen: false)
        mover.move(to: move)
        direction *= -1
    }
}
