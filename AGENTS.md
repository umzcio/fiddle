# Working on fiddle

Standing context for anyone, human or agent, making changes in this repo. Read
it before touching code.

fiddle is a native macOS auto-clicker and mouse jiggler with an early-2000s
skeuomorphic UI, an affectionate homage to the Nero StartSmart launcher.

## Architecture

The UI is a single HTML file hosted in a `WKWebView`. All real work happens in
a native, UI-agnostic Swift engine. The two halves talk over a small typed
bridge.

This split is deliberate: recreating the glossy chrome with hand-drawn SwiftUI
shapes would be a large effort with real fidelity risk, and keeping the engine
UI-free makes it testable without a web view. Do not move engine logic into the
web layer or vice versa.

```
Fiddle/
  UI/
    MainWindow.swift        borderless window host
    MenuBar.swift           status item and popover
    web/index.html          the live UI markup and styles
    web/app.js              the live UI script (external so the CSP forbids inline script)
  Bridge/
    Bridge.swift            WKScriptMessageHandler, owns the web view
    Protocol.swift          Codable Command and Event types, the contract
    FiddleController.swift  routes Commands to engines, emits Events
  Engine/                   click, jiggle, wake lock, anti-AFK, playback,
                            recorder, key, hotkeys, permissions, power,
                            idle, position picker
  Models/                   Settings, Macro, Profile, Recording
FiddleTests/                XCTest suite
design/fiddle-mockup.html   visual source of truth, do not edit for behavior
```

Two web surfaces (the main window and the menu-bar popover) share one
`FiddleController`. Events are broadcast to every registered sink, with an
`excluding:` variant so the surface that sent a command does not get its own
form re-rendered underneath the user.

## The bridge contract

Web to Swift, via `window.webkit.messageHandlers.fiddle.postMessage({...})`:
`ready`, `start`, `stop`, `updateConfig`, `pickPosition`, `setHotkey`,
`resetHotkeys`, `setPref`, `checkPermissions`, `openSettings`, `window`,
`recordStart`, `recordStop`, `clearRecording`, `saveMacros`, `saveProfiles`,
`applyProfile`.

Swift to web, via `webView.evaluateJavaScript("window.fiddleEvent(<json>)")`:
`status`, `permissions`, `positionPicked`, `error`, `config`, `prefs`,
`hotkeys`, `recording`, `macros`, `profiles`, `log`.

`Fiddle/Bridge/Protocol.swift` is the authoritative definition of both halves.
If you change a message, change it there first and keep the JS in
`Fiddle/UI/web/app.js` in step.

Numbers crossing the bridge are decoded as Swift `Int`. A fractional JSON
number fails the decode and the whole command is dropped silently, so the web
side rounds every numeric before sending.

## macOS platform notes

These are the things that will bite you if missed.

- **Permissions.** Synthesizing or tapping input requires Accessibility
  (`AXIsProcessTrustedWithOptions`). The recorder also needs Input Monitoring.
  Detect a missing permission, tell the user, and deep-link to the right
  System Settings pane. Anything that posts events must guard on this first:
  without the grant, macOS silently discards the events and the UI would
  otherwise claim to be running while nothing happens.
- **Event synthesis.** Use
  `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` and
  `.post(tap: .cghidEventTap)`. For a double click, post the pair twice and set
  `.mouseEventClickState` to 2 on the second. Tag synthesized events with
  `SyntheticEvents.userDataTag` so fiddle's own taps can ignore them.
- **Timing.** Do not use `Timer` for fast intervals. Use a
  `DispatchSourceTimer` with zero leeway on a dedicated queue. Keep the click
  loop off the main thread and marshal only status changes back to the main
  actor. Both posting engines floor their interval at 10 ms; never bypass the
  clamp at a call site.
- **Sleep prevention.** Use IOKit power assertions
  (`IOPMAssertionCreateWithName`). Always release on stop and on quit. A leaked
  assertion keeps the user's display awake forever, which is why tests must
  never construct an engine with `keepAwake: true`.
- **Idle detection.** Read seconds since last input via
  `CGEventSource.secondsSinceLastEventType`. Note that fiddle's own posted
  events reset the system idle clock, so idle-only mode tracks user activity
  separately from its own nudges.
- **Zen jiggle.** Move by the configured distance, then move back, so the
  pointer does not walk across the screen over hours.
- **Global hotkeys.** Provided by the `KeyboardShortcuts` package. Always keep
  a panic key that force-stops every engine.
- **No sandbox.** The App Sandbox blocks global event posting and tapping. Do
  not enable it. The app ships non-sandboxed with hardened runtime, Developer
  ID signed and notarized. Enabling the sandbox breaks every feature with no
  obvious error message.

## Conventions

- Keep the Engine layer free of UI and web concerns. It must compile and
  unit-test without the web view. The bridge is the only layer that knows both
  sides.
- Prefer async/await and structured concurrency. No force unwraps on any path
  that depends on permissions, OS calls, or user input.
- One responsibility per file, named for what it does. Log with `os.Logger`,
  one category per subsystem.
- Persist settings as a single Codable `Settings` value. Every persisted or
  bridged struct gets a hand-written `init(from:)` using `decodeIfPresent` with
  defaults, so old saved data never fails to decode and reset the user's
  settings.
- Always release power assertions and tear down event taps on stop and on app
  termination.
- The visual design is fixed. `design/fiddle-mockup.html` is the spec. Match
  its layout, colors, gradients, and chrome. Do not redesign it.
- American spelling. No em dashes in user-facing copy, comments, or docs; use
  commas or periods.
- The product name is lowercase "fiddle" in all user-facing text.

## Build and test

```bash
# Open in Xcode and press Run, or from the command line:
xcodebuild -scheme Fiddle -configuration Debug \
  -derivedDataPath build \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -destination 'platform=macOS' test
```

The project pins the maintainer's Developer ID signing identity; if you do not
have that certificate, add the signing overrides shown in the README's "Build
from source" section to the same command.

First run prompts for Accessibility permission. Grant it in System Settings,
then relaunch.

The web UI can also be opened directly in a browser for quick layout work.
Serve `Fiddle/UI/web/` over `python3 -m http.server` and load `index.html`;
the native bridge is absent, so `send()` logs to the console instead. Behavior
that depends on the engine has to be verified in the real app.
