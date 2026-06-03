//
//  WakeLockEngine.swift
//  Fiddle
//
//  Keeps the Mac awake by holding IOKit power assertions. No timer, no cursor
//  movement -- the assertion alone prevents idle sleep.
//

final class WakeLockEngine {
    private let display = PowerAssertion(kind: .displaySleep)
    private let system = PowerAssertion(kind: .systemSleep)

    func start(config: WakeLockConfig) {
        stop()
        if config.keepDisplayAwake { display.acquire(reason: "fiddle Wake Lock") }
        if config.keepSystemAwake { system.acquire(reason: "fiddle Wake Lock") }
    }

    func stop() {
        display.release()
        system.release()
    }
}
