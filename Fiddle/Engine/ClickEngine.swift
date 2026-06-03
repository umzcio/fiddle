//
//  ClickEngine.swift
//  Fiddle
//
//  Synthesizes mouse clicks on a precise interval. The timing-critical loop runs
//  on a dedicated high-priority queue via a DispatchSourceTimer with zero leeway;
//  only completion is marshalled back to the main actor.
//
//  The pure decision logic (counting, target resolution, event mapping) is kept
//  in value types so it can be tested without posting real events.
//

import CoreGraphics
import Foundation

// MARK: - Pure logic (unit tested)

/// Translates the abstract button/click-type into Core Graphics event values.
enum ClickMapping {
    static func cgButton(_ button: MouseButton) -> CGMouseButton {
        switch button {
        case .left:   return .left
        case .right:  return .right
        case .middle: return .center
        }
    }

    static func downType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left:   return .leftMouseDown
        case .right:  return .rightMouseDown
        case .middle: return .otherMouseDown
        }
    }

    static func upType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left:   return .leftMouseUp
        case .right:  return .rightMouseUp
        case .middle: return .otherMouseUp
        }
    }

    /// 2 for a double click, 1 otherwise.
    static func clickState(_ clickType: ClickType) -> Int64 {
        clickType == .double ? 2 : 1
    }
}

/// Tracks an in-flight click run and decides when it is finished.
struct ClickRunState {
    let config: ClickerConfig
    private(set) var count = 0

    init(config: ClickerConfig) { self.config = config }

    /// The fixed target, or nil when clicking at the current cursor location.
    var targetPoint: CGPoint? {
        config.position == .fixed ? CGPoint(x: config.x, y: config.y) : nil
    }

    /// Record one click. Returns true if the run should continue.
    mutating func recordClick() -> Bool {
        count += 1
        guard config.repeat == .times else { return true }
        return count < config.times
    }
}

// MARK: - Event posting seam

protocol MouseEventPosting {
    func currentLocation() -> CGPoint
    func postClick(button: MouseButton, clickType: ClickType, at point: CGPoint)
}

struct CGEventMousePoster: MouseEventPosting {
    private let source = CGEventSource(stateID: .combinedSessionState)

    func currentLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func postClick(button: MouseButton, clickType: ClickType, at point: CGPoint) {
        let source = self.source
        let cgButton = ClickMapping.cgButton(button)
        let downType = ClickMapping.downType(button)
        let upType = ClickMapping.upType(button)

        func postPair(clickState: Int64) {
            if let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: cgButton) {
                down.setIntegerValueField(.mouseEventClickState, value: clickState)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: cgButton) {
                up.setIntegerValueField(.mouseEventClickState, value: clickState)
                up.post(tap: .cghidEventTap)
            }
        }

        if clickType == .double {
            postPair(clickState: 1)
            postPair(clickState: 2)
        } else {
            postPair(clickState: 1)
        }
    }
}

// MARK: - Engine

final class ClickEngine {
    private let poster: MouseEventPosting
    private let queue = DispatchQueue(label: "edu.umontana.fiddle.clickengine", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var runState: ClickRunState?
    private var running = false

    /// Called on the main actor when a bounded ("repeat N times") run completes.
    var onFinished: (@MainActor () -> Void)?

    /// Called on the main actor after each click is posted, when set. The
    /// controller wires this to the click sound only while the pref is on, so a
    /// disabled sound costs zero per-click work.
    var onClick: (@MainActor () -> Void)?

    init(poster: MouseEventPosting = CGEventMousePoster()) {
        self.poster = poster
    }

    func start(config: ClickerConfig) {
        stop()
        let interval = max(1, config.intervalMs)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(interval),
                       repeating: .milliseconds(interval),
                       leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in self?.fire() }
        queue.sync {
            self.runState = ClickRunState(config: config)
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
        let point = state.targetPoint ?? poster.currentLocation()
        poster.postClick(button: state.config.button, clickType: state.config.clickType, at: point)
        if let onClick { Task { @MainActor in onClick() } }
        let shouldContinue = state.recordClick()
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
