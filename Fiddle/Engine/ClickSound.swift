//
//  ClickSound.swift
//  Fiddle
//
//  Plays a short feedback sound per click when the user enables "Sound on click".
//  Uses a built-in system sound so no audio asset needs bundling.
//

import AppKit

@MainActor
final class ClickSound {
    private let sound = NSSound(named: NSSound.Name("Tink"))

    func play() {
        guard let sound else { return }
        sound.stop()   // restart so rapid clicks each tick
        sound.play()
    }
}
