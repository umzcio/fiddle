# fiddle Code Review

Multi-agent review performed 2026-06-10. Six parallel scout agents (events/taps, power/permissions/hotkeys, WebView bridge, concurrency, persistence, dead code) produced 40 unique candidate findings after dedup; an independent verification agent re-read every cited line plus callers and guards, performed a mandated second pass, and confirmed all 40 (7 with corrections). Review only, no fixes applied.

Severity definitions: **Critical** = security issue, stuck input/power state (leaked assertion, unstoppable engine, panic key failure), data loss, or crash on realistic input. **Major** = wrong behavior or significant degradation with a workaround. **Minor** = quality/maintenance improvement.

## Remediation Tracking

| ID | Title | Severity | Status | Commit |
|---|---|---|---|---|
| C1 | Stop mid-playback leaves synthesized button stuck down | Critical | FIXED | dccc793 |
| C2 | Panic/stopAll never stop the recorder tap | Critical | FIXED | b1e73cd |
| C3 | No duplicate-combo guard in setHotkey | Critical | FIXED | 6b11cec |
| M1 | PlaybackEngine restart race (no run identity) | Major | FIXED | 45f1cae |
| M2 | Playback/macro double-clicks missing clickState | Major | FIXED | c4abaee |
| M3 | Recorder captures fiddle's own synthesized events | Major | FIXED | d81376e |
| M4 | CGWarpMouseCursorPosition generates no events | Major | FIXED | 764adc8 |
| M5 | beginRecording reports active when tap creation failed | Major | FIXED | 81ec0b6 |
| M6 | updateConfig/setPref never rebroadcast (surface desync) | Major | FIXED | 00b0cfc |
| M7 | start() early returns leave status stuck Running | Major | FIXED | 8be3693 |
| M8 | Four views never persist(); recorder config can never persist | Major | FIXED | 3bb730a |
| m1 | Recording unbounded, lives in settings blob | Minor | FIXED (cap; storage move in FOLLOWUP) | a0da6c3 |
| m2 | Wake Lock "Running" with zero assertions | Minor | FIXED | 255b445 |
| m3 | Modifier-less hotkeys accepted | Minor | FIXED | 5239c19 |
| m4 | Login-item failures swallowed; dead pref field | Minor | FIXED | ce1344d |
| m5 | Engines keep "Running" after AX revocation | Minor | FIXED | 1dabee2 |
| m6 | Activity log unescaped innerHTML | Minor | FIXED | 774b937 |
| m7 | ready/applyProfile re-render + re-center main window | Minor | FIXED | 9570f92 |
| m8 | ClickEngine.onClick unsynchronized | Minor | FIXED | ba9beb4 |
| m9 | Stale onFinished marks fresh run idle | Minor | FIXED | e1a5d36 |
| m10 | Zen restore warps to stale origin | Minor | FIXED | 9e2a46a |
| m11 | beginRecording stops playback without status update | Minor | FIXED | 8be3693 |
| m12 | No screen-bounds validation on playback/fixed position | Minor | FIXED | 1aae3e2 |
| m13 | Corrupt nested value silently resets all settings | Minor | FIXED | d73d6c0 |
| m14 | menuBarOnly: window still shown at launch | Minor | FIXED | de50930 |
| m15 | applyProfile does six full blob writes | Minor | FIXED | 554f10f |
| m16 | Position picker tap failure swallowed | Minor | FIXED | cbb8bfc |
| m17 | pointInsideAppWindow lacks z-order check | Minor | FIXED | 00b5f69 |
| m18 | Recorder does not capture drags | Minor | DEFERRED (feature work; sketch in FOLLOWUP.md) | |
| m19 | Dead "Save profile" dock orb | Minor | FIXED | 3001441 |
| m20 | WebContainerView unreferenced | Minor | FIXED | ef4f68f |
| m21 | hotkeyTriggered event is a no-op | Minor | FIXED | a83d0cb |
| m22 | Unused Logger properties | Minor | FIXED | 6ba1fa5 |
| m23 | PrefValue.encode unreachable | Minor | FIXED | 675a5ba |
| m24 | AntiAFKEngine duplicates JiggleEngine | Minor | DEFERRED (engine restructure; sketch in FOLLOWUP.md) | |
| m25 | ClickEngine/KeyEngine boilerplate duplication | Minor | DEFERRED (engine restructure; sketch in FOLLOWUP.md) | |
| m26 | ClickRecorder/PositionPicker tap boilerplate duplication | Minor | DEFERRED (C-callback lifetime refactor; sketch in FOLLOWUP.md) | |
| m27 | Duplicated JS key-capture logic | Minor | DEFERRED (m3 made the flows deliberately divergent; FOLLOWUP.md) | |
| m28 | Hotkey defaults defined in three places | Minor | FIXED | 737c7cd |
| m29 | Undefined CSS var --font-body | Minor | FIXED | fa142e0 |
| m30 | Chevron orbs styled clickable, never wired | Minor | FIXED | 710e4e8 |
| m31 | Stale scaffold comments | Minor | FIXED | 5dc1494 |

## Summary

| Category | Critical | Major | Minor | Total |
|---|---|---|---|---|
| Events & Taps | 1 | 4 | 1 | 6 |
| Power & Permissions | 2 | 1 | 4 | 7 |
| WebView Bridge | 0 | 1 | 2 | 3 |
| Concurrency | 0 | 1 | 4 | 5 |
| Persistence | 0 | 0 | 5 | 5 |
| Dead Code & Quality | 0 | 1 | 13 | 14 |
| **Total** | **3** | **8** | **29** | **40** |

---

## Critical

### C1. Stopping playback mid-sequence leaves a synthesized mouse button stuck down

`Fiddle/Engine/PlaybackEngine.swift:104-120`

```swift
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
```

**Category:** Events & Taps. **Class:** stuck input state on cancellation path.

**Why:** Recordings store `down` and `up` as separate events with real inter-event delays. If `stop()` (UI stop, mode switch, or the panic hotkey via `FiddleController.panic()` at `FiddleController.swift:286-291`) lands while the loop is sleeping between a posted `down` and its `up`, the loop returns without posting the matching `up`. The HID system is left with a synthetic button logically pressed; the next real click behaves as a drag or second press. The panic key, whose job is "halt safely," is the most likely trigger.

**Severity:** Critical.

**Fix:** Track buttons with an unmatched posted `down` during the pass; on every early `return` from `playLoop`, post the corresponding `up` events at the last posted location before exiting.

### C2. Panic key and stopAll() never stop the click recorder's event tap

`Fiddle/Bridge/FiddleController.swift:125-128, 286-291`

```swift
private func stopEngines() {
    clickEngine.stop(); jiggleEngine.stop(); wakeLockEngine.stop()
    antiAFKEngine.stop(); playbackEngine.stop(); keyEngine.stop()
}
...
private func panic() {
    stopAll()
    logActivity("Panic: all automation halted", level: "warn")
    picker.cancel()
    broadcast(.hotkeyTriggered(action: .panic))
}
```

**Category:** Power & Permissions. **Class:** panic-path completeness gap.

**Why:** `stopEngines()` covers six engines but omits `clickRecorder`. `shutdown()` (`FiddleController.swift:380-384`) does stop it, proving the omission is specific to the panic/stop path. User starts a recording, hits Cmd+Escape: the system-wide listen-only tap keeps capturing every click, the UI still shows recording active, and the activity log claims "all automation halted."

**Severity:** Critical.

**Fix:** In `panic()` (and `stopAll()`), when `clickRecorder.isRecording`, run the `endRecording()` logic (stop, persist via `store.setRecording`, `emitRecording()`) so the tap is torn down and the UI reflects it.

### C3. No duplicate-combo guard in setHotkey: the panic binding can be shadowed, then silently destroyed

`Fiddle/Bridge/FiddleController.swift:249-257`

```swift
private func setHotkey(action: HotkeyAction, combo: String) {
    guard let shortcut = HotkeyCombo.parse(combo) else {
        broadcast(.error(message: "That key combination is not supported."))
        emitHotkeys()
        return
    }
    hotkeys.setShortcut(shortcut, for: action)
    emitHotkeys()
}
```

**Category:** Power & Permissions. **Class:** registration conflict / panic key failure.

**Why:** Verified against the vendored KeyboardShortcuts package: `handleOnKeyDown` invokes the handler of every name bound to the pressed shortcut, and `userDefaultsSet` unconditionally unregisters a name's old shortcut. Two concrete failures: (a) rebind startStop to cmd+Escape and one press fires both `panic()` and `toggleStartStop()`; dictionary iteration order is unspecified, so the panic key can restart automation immediately after stopping it. (b) Rebind startStop away again, and the package unregisters the cmd+Escape Carbon hotkey that panic still depends on. The panic key is dead until relaunch.

**Severity:** Critical.

**Fix:** In `setHotkey`, compare the parsed shortcut against the bindings of the other three actions and reject with the existing `.error` event on a match.

---

## Major

### M1. PlaybackEngine restart race: no run identity, so an old worker thread can double-post or kill the new run

`Fiddle/Engine/PlaybackEngine.swift:71-93, 100-133` (found independently by two agents)

```swift
func start(events: [RecordedEvent], config: RecorderConfig) {
    stop()
    ...
    self.running = true
    ...
}
private func playLoop() {
    while isRunning() { ... }
    lock.lock(); running = false; runState = nil; lock.unlock()
```

**Category:** Events & Taps / Concurrency. **Class:** CWE-362 race condition (no generation token).

**Why:** `running` is a single Bool. `FiddleController.start` always does stop-then-start back to back; the old worker spends its life in 25ms sleep slices, wakes after `running` has flipped false-then-true, and keeps replaying its stale snapshot concurrently with the new worker, double-posting events and corrupting the shared `runState` pass counter. Alternatively, a naturally finishing old worker's unconditional `running = false` cleanup kills the new run while the controller status stays `.running` forever (the abort path skips `onFinished`).

**Severity:** Major.

**Fix:** Add a monotonically increasing generation counter under the lock; `start()` increments it and hands the value to the worker; every `isRunning()` check, the end-of-loop cleanup, and the `onFinished` dispatch compare against the current generation.

### M2. Playback and macro double-clicks never set .mouseEventClickState, so they do not register as double-clicks

`Fiddle/Engine/PlaybackEngine.swift:39-46`, `Fiddle/Models/Macro.swift:76-81`, `Fiddle/Engine/ClickRecorder.swift:53-55`

```swift
func post(button: MouseButton, down: Bool, at point: CGPoint) {
    ...
    if let event = CGEvent(mouseEventSource: source, mouseType: type,
                           mouseCursorPosition: point, mouseButton: cgButton) {
        event.post(tap: .cghidEventTap)
    }
}
```

**Category:** Events & Taps. **Class:** event synthesis correctness.

**Why:** macOS apps detect double-clicks via the event's clickState field, not timing alone. `CGSingleEventPoster.post` never sets it, `MacroCompiler` emits a "double click" as two plain pairs, and `RecordedEvent` has no clickState field, so recorded real double-clicks replay as two singles. ClickEngine does this correctly (`ClickEngine.swift:90-106`), proving the requirement is known; the playback path skips it.

**Severity:** Major.

**Fix:** Capture `event.getIntegerValueField(.mouseEventClickState)` into `RecordedEvent`, emit clickState 1 then 2 from `MacroCompiler` for doubles, and set the field on both down and up in `CGSingleEventPoster.post`.

### M3. Recorder captures fiddle's own synthesized events: nothing tags synthetic events, and engines keep running while recording

`Fiddle/Bridge/FiddleController.swift:125-128, 388-398`, `Fiddle/Engine/ClickRecorder.swift:80-91` (found independently by two agents)

```swift
playbackEngine.stop()        // beginRecording stops ONLY playback
clickRecorder.start()
```
```swift
guard isRecording, let mapped = RecordEventMapping.event(for: type) else { return }
if exclude?(location) == true { return }   // window-position filter only
```

**Category:** Events & Taps. **Class:** synthesized-event feedback loop.

**Why:** No synthesized event carries a marker (zero `eventSourceUserData` hits in the codebase); the only filter is window-frame position. The clicker posts to `.cghidEventTap`, which the `.cgSessionEventTap` listen-only recorder sees. `beginRecording` stops only playback, and `toggleStartStop` has no recording guard, so the armed recorder captures the clicker's output as if it were user input. With playback the loop self-amplifies: stopping the recording overwrites the saved recording with one containing its own replayed events.

**Severity:** Major.

**Fix:** Two layers: (a) stop all engines (or refuse start) while `clickRecorder.isRecording`; (b) tag every synthesized event via `setIntegerValueField(.eventSourceUserData, value: <sentinel>)` in both posters and drop sentinel events in the recorder callback.

### M4. Jiggler and Anti-AFK use CGWarpMouseCursorPosition, which generates no events, so jiggling without keepAwake prevents nothing

`Fiddle/Engine/JiggleEngine.swift:43-47` (shared by `AntiAFKEngine.swift:21, 50-57`) (found independently by two agents)

```swift
func move(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGAssociateMouseAndMouseCursorPosition(1)
}
```

**Category:** Events & Taps. **Class:** API misuse / feature efficacy.

**Why:** `CGWarpMouseCursorPosition` is documented to move the cursor without generating events; it does not reset the HID idle timer. With `keepAwake == false` (a valid config) the jiggler visibly twitches the pointer while the Mac sleeps on schedule, defeating its headline purpose. Anti-AFK likewise produces no input events for apps that watch events rather than polling cursor position. Only the optional IOKit assertion does real work. (Verified flip side: because no events post, idle-only mode is not self-defeating today.)

**Severity:** Major.

**Fix:** Post a real `.mouseMoved` CGEvent via `.cghidEventTap` (as `CGSingleEventPoster.move` already does) instead of or alongside the warp. The idle-only check already runs before the nudge in the same tick; keep it that way once events reset the idle clock, and filter the app's own events from idle detection if needed.

### M5. beginRecording reports recording active even when the event tap was never created

`Fiddle/Engine/ClickRecorder.swift:39-61`, `Fiddle/Bridge/FiddleController.swift:395-397` (found independently by two agents)

```swift
guard let tap = CGEvent.tapCreate(...) else {
    return            // silent failure
}
```
```swift
clickRecorder.start()
broadcast(.recording(active: true, steps: ...))   // unconditional
```

**Category:** Power & Permissions. **Class:** silent failure / data loss.

**Why:** The window is real, not theoretical: the project's own comment (`Permissions.swift:33-34`) documents that after granting Input Monitoring mid-session, `IOHIDCheckAccess` reports granted while tap creation still fails until relaunch. The permission guard passes, the tap never exists, and the UI shows an active recording that captures nothing. The user's recording session is silently lost. `ClickRecorder.isRecording` exists but is never checked here.

**Severity:** Major.

**Fix:** After `clickRecorder.start()`, check `clickRecorder.isRecording`; on false, broadcast `.error("Recording could not start. If you just granted Input Monitoring, quit and relaunch fiddle.")` and emit `recording(active: false)`.

### M6. updateConfig and setPref are persisted but never rebroadcast, so the two live skins desync and the stale surface overwrites fresh edits

`Fiddle/Bridge/FiddleController.swift:96, 110-119, 356-365`, `Fiddle/UI/web/index.html:738, 1374-1377`

```swift
case .updateConfig(let mode, let config): saveConfig(mode: mode, config: config)
// saveConfig writes the store; no broadcast anywhere in this path
```

**Category:** WebView Bridge. **Class:** state synchronization gap.

**Why:** Each surface (main window, menu-bar popover) keeps independent JS state; `.config`/`.prefs` events are pushed only on `ready` and `applyProfile`. Edit the click rate in the popover, then press START in the main window: start sends the main window's stale state, and `start()` begins with `saveConfig`, so the engine runs the old interval and the popover's edit is reverted in the store. Skin changes likewise never reach the other surface until the next `ready`.

**Severity:** Major.

**Fix:** After `saveConfig` in `.updateConfig`, `broadcast(.config(mode:config:))`; after `applyPref`, broadcast the `.prefs` event (as `applyProfile` already does). The JS `applyConfig`/`applyPrefs` are idempotent; optionally broadcast to all-but-sender.

### M7. start() early-return paths stop all engines but leave status stuck on "Running"

`Fiddle/Bridge/FiddleController.swift:130-141` (same shape at 160-191, 195-205)

```swift
private func start(mode: AutomationMode, config: Config) {
    saveConfig(mode: mode, config: config)
    stopEngines()
    switch mode {
    case .clicker:
        guard permissions.accessibilityTrusted(promptIfNeeded: true) else {
            emitPermissions()
            broadcast(.error(message: "Accessibility permission is required to click."))
            return        // no setStatus(.idle)
        }
```

**Category:** Concurrency / lifecycle. **Class:** state machine desync.

**Why:** `stopEngines()` runs before every guard. Realistic path: jiggler running (needs no permission), user starts the clicker without Accessibility, or plays an empty recording, or starts a missing macro. Every engine is already stopped, no `setStatus(.idle)` runs, so the LED, the menu-bar icon, and `toggleStartStop()` all believe automation is running. The next hotkey press "stops" nothing instead of starting.

**Severity:** Major.

**Fix:** Call `setStatus(.idle)` immediately after `stopEngines()` (a no-op broadcast when already idle), or convert each early return to `{ setStatus(.idle); return }`.

### M8. Keyboard, Wake Lock, Anti-AFK, and Recorder forms never call persist(); recorder config can never persist at all

`Fiddle/UI/web/index.html:843-846, 891-892, 908-911, 947-948` vs the contract at 734-738; `Fiddle/Bridge/FiddleController.swift:356-365, 373`

```js
// index.html:734-737 — the documented contract
// Persist the current mode's config immediately, so any start path (global
// hotkey, menu bar, the flame) uses what the user actually set rather than the
// last-started snapshot.
bind('kv-h', v=>k.hrs=+v||0);   // keyboard: no persist()
toggle('wl-disp', v=>w.keepDisplay=v);   // wake lock: no persist()
```

**Category:** Dead Code & Quality (behavioral). **Class:** stale-config start.

**Why:** Clicker and jiggler honor the contract; the other four views do not. Edit the keyboard press interval, then press the global Start/Stop hotkey: `toggleStartStop()` reads the store and runs the pre-edit value, exactly the bug the comment warns about. Verification found it is worse for the recorder: `saveConfig` has no `.recorder` case and `config(for: .recorder)` is hardcoded `(.until, 1)` (`FiddleController.swift:373`), so recorder repeat/times settings can never persist through any path.

**Severity:** Major.

**Fix:** Append `persist()` to each handler, matching the clicker/jiggler pattern; add a `.recorder` case to `saveConfig` and store the recorder config instead of hardcoding it.

---

## Minor

### m1. Recording has no size cap and lives inside the single settings blob rewritten on every save
`Fiddle/Engine/ClickRecorder.swift:86-90`, `Fiddle/Models/Settings.swift:139-146`. Events append unbounded and the whole blob (recording + macros + profiles) is re-encoded synchronously on the main thread on every pref toggle. Growth is bounded by click count (the tap captures only downs/ups), so this is hygiene rather than a guaranteed blowup, and it compounds with M3's self-recording loop. **Fix:** cap events (auto-stop with an error event) and move the recording to its own storage key.

### m2. Wake Lock runs as "Running" while holding zero assertions
`Fiddle/Engine/WakeLockEngine.swift:13-17`, `FiddleController.swift:150-154`. Both toggles off is a valid config; START flips the LED to Running while nothing keeps the Mac awake. **Fix:** reject a both-false config with an `.error` event and stay idle.

### m3. Modifier-less letter/digit hotkeys are accepted, swallowing that key system-wide
`Fiddle/Engine/HotkeyCombo.swift:53-69`, `index.html:1191-1207`. Binding bare `KeyA` registers a Carbon hotkey that consumes the letter A in every app. The bundled package's own recorder UI enforces modifiers; this bridge path bypasses it. **Fix:** require a modifier unless the key is a function key or Escape.

### m4. Launch-at-login failures are swallowed; the stored pref is write-only dead state
`Fiddle/Engine/LoginItem.swift:14-26`, `FiddleController.swift:110-113`, `Settings.swift:14, 125` (found by three agents). `setEnabled` only logs; the pref is persisted before the call and never read anywhere (`pushInitialState` correctly reports live `SMAppService` status); `.requiresApproval` reads as disabled with no guidance. **Fix:** return the outcome from `setEnabled`, broadcast `.error` plus corrected prefs on failure, open the Login Items pane for `.requiresApproval`, and delete or reconcile `prefs.launchAtLogin`.

### m5. Engines keep "Running" after mid-run Accessibility revocation
`FiddleController.swift:136`, `ClickEngine.swift:157-160`. Permission is checked only at start; revoking AX mid-run silently drops every posted event while the timer fires and the LED shows Running. **Fix:** in `recheckPermissions()` (already called on activation), `stopAll()` with an error event when a posting engine runs without trust.

### m6. Activity log renders messages with unescaped innerHTML; profile names reach it
`index.html:1124-1127` (sink), `FiddleController.swift:458` (source), `index.html:1107` (user input). CWE-79 (self-XSS into the privileged skin). The Swift-to-JS transport is correctly JSON-escaped; the gap is the JS render: `${a.message}` raw in `innerHTML` while `esc()` exists and is used for the same names elsewhere. Only the local user's own typed profile name reaches it, hence Minor. **Fix:** `${esc(a.message)}`.

### m7. Any surface's `ready` (and every applyProfile) re-renders the main window and re-centers it
`FiddleController.swift:341-354, 457`, `index.html:1314-1329, 1501`, `MainWindow.swift:165-170`. First popover open broadcasts `.prefs` to all sinks; the main window rebuilds its view (losing focus/scroll) and `fitToContent` unconditionally calls `window.center()`, yanking a user-positioned window to screen center. **Fix:** reply to `ready` only on the requesting sink; center only on first layout.

### m8. ClickEngine.onClick is written on the main thread while read on the click queue, unsynchronized
`ClickEngine.swift:125, 161`, `FiddleController.swift:79-85` (found by two agents). CWE-362/CWE-820. Toggling the click-sound pref mid-run races the closure write against the timer's read; every other ClickEngine field is queue-confined, this one is not. **Fix:** set it through `queue.sync` or a lock.

### m9. Stale onFinished completion can mark a freshly started run of the same mode idle
`FiddleController.swift:63-66`. The guard checks only `lastMode`, not run identity; a bounded run's completion Task can land after a stop+restart (main-actor Tasks stall during menu tracking) and flip a live run's UI to Idle. **Fix:** a run-generation counter captured per start, checked in the completion.

### m10. Zen-mode restore warps the cursor to a stale origin
`JiggleEngine.swift:95-104` (found by two agents). The 40ms-delayed restore guards only `config != nil`: stop+start inside the window passes the guard and warps to the previous run's origin; with idleOnly off it also warps out from under a user who started moving. **Fix:** per-run generation token; only restore if the cursor is still at the nudge target.

### m11. beginRecording stops a running playback without updating run status
`FiddleController.swift:388-398` vs `stopAll()` at 214-217. Starting a recording during playback kills the engine but leaves the LED on Running; the next hotkey press no-ops. **Fix:** call `stopAll()` when `status == .running`.

### m12. Playback and fixed-position clicks post absolute coordinates with no screen-bounds validation
`PlaybackEngine.swift:115-120`, `ClickEngine.swift:159-160`. CWE-20 flavor. Recordings or fixed positions from a detached display replay pinned at screen edges, clicking whatever lives there, indefinitely with repeat-until. Requires a display change plus a user start, and panic stops it. **Fix:** validate targets against the union of `NSScreen.screens` (Quartz coordinates) before starting; refuse with an error.

### m13. A single corrupt nested value silently resets all settings; the backup key has no restore path
`Settings.swift:74-83, 95-105`. One bad profile element throws the whole decode; fallback to defaults with no UI notice; `fiddle.settings.v1.backup` is written and never read anywhere. **Fix:** lossy per-element array decoding, an `.error` broadcast on fallback, and a restore-from-backup attempt.

### m14. menuBarOnly is half-applied at launch: the main window is shown anyway
`FiddleApp.swift:35-38`, `FiddleController.swift:74-77`, `MainWindow.swift:109-112`. The pref hides the Dock icon but `wc.show()` activates and fronts the window on every launch, worst with launchAtLogin. **Fix:** gate the initial `show()` on `menuBarOnly == false`.

### m15. applyProfile performs six consecutive full re-encodes of the entire settings blob
`FiddleController.swift:444-449`, `Settings.swift:139-146`. Each setter calls `save()`; compounds with m1. **Fix:** a batched `SettingsStore.update { ... }` with one save.

### m16. Position picker tap-create failure is swallowed; the UI waits forever
`PositionPicker.swift:27-51`, `FiddleController.swift:295-302`. JS has already flipped to Pick mode; on tap failure no `positionPicked` or `error` ever arrives. **Fix:** check `picker.isPicking` after `begin()` and broadcast `.error`.

### m17. pointInsideAppWindow is frame-containment only, no z-order
`FiddleController.swift:481-490`. Clicks on another app's window overlapping fiddle's frame are silently dropped from recordings (the coordinate flip itself was verified correct, including negative-origin displays). **Fix:** resolve the topmost window at the point via `CGWindowListCopyWindowInfo` and compare its owner PID.

### m18. Recorder does not capture drag events, so recorded drags replay broken
`ClickRecorder.swift:33-36`. The tap mask omits dragged event types; a drag becomes down-at-A teleport up-at-B, and the only move type the poster emits is `.mouseMoved`, wrong while a button is down. **Fix:** add dragged types (coalesced) to the mask and emit per-button dragged events on replay.

### m19. Dock "Save profile" orb is a dead control
`index.html:541-543` (element), `:1597` (only the info orb is wired). Styled clickable (`cursor:pointer`), does nothing; a working save flow exists in the Profiles view. **Fix:** wire it to the same capture-and-save logic, or remove it.

### m20. WebContainerView is an unreferenced type
`Fiddle/UI/WebContainerView.swift:14-19`. Referenced only by its own file and the pbxproj; the popover uses `PopoverContainer` instead. **Fix:** delete; resurrect from git when a settings window exists.

### m21. hotkeyTriggered event pathway produces no observable behavior
`FiddleController.swift:273, 278, 290`; `index.html:1537` is an explicit no-op consumer. **Fix:** implement the keycap flash or delete the case, broadcasts, and JS arm.

### m22. Unused Logger properties
`FiddleController.swift:50`, `MainWindow.swift:49`. Zero `log.` call sites in either file. **Fix:** delete, or log the existing error paths.

### m23. PrefValue.encode(to:) is unreachable
`Protocol.swift:149-156`. `PrefValue` rides only the Decodable `Command`; nothing encodes it. **Fix:** declare it `Decodable` only and drop the encoder.

### m24. AntiAFKEngine is a strict subset duplicate of JiggleEngine
`AntiAFKEngine.swift:25-57` vs `JiggleEngine.swift:65-108`. Same timer/queue/nudge/direction logic minus zen and idle-only; CLAUDE.md itself calls Anti-AFK a jiggler preset. **Fix:** route Anti-AFK through JiggleEngine (`mode: .visible, idleOnly: false`) or extract a shared nudge core.

### m25. ClickEngine and KeyEngine duplicate timer/run-state boilerplate nearly line for line
`ClickEngine.swift:131-172` vs `KeyEngine.swift:86-127`, plus twin `recordClick()`/`recordPress()` count logic. **Fix:** extract a generic repeating-timer engine parameterized by a per-tick closure.

### m26. ClickRecorder and PositionPicker duplicate the listen-only tap boilerplate
`ClickRecorder.swift:28-78` vs `PositionPicker.swift:22-65`, including byte-identical timeout-recovery blocks. **Fix:** extract a `ListenOnlyTap` helper owning create/enable/teardown/recovery.

### m27. Duplicated JS key-capture logic
`index.html:804-821` (`beginKeyCapture`) vs `:1177-1207` (`beginCapture`/`onCaptureKey`): two parallel capture state machines that `selectCat` must tear down separately. **Fix:** one shared `captureCombo(btn, onDone)` helper.

### m28. Hotkey defaults defined in three places
`HotkeyManager.swift:15-18`, `index.html:635`, `index.html:1209`. Swift already pushes real bindings on `ready`; the JS copies are redundant and can drift. **Fix:** make Swift the single source; have reset send a command whose defaults live beside HotkeyManager's.

### m29. CSS variable --font-body is used but never defined
`index.html:361, 438` use it; `:root` (33-34) defines only `--font-ui`/`--font-disp`. Two controls silently render in the inherited font. **Fix:** replace with `var(--font-ui)`.

### m30. Sidebar chevron orbs styled clickable but never wired
`index.html:503` markup, `:262-268` CSS (`cursor:pointer`); no handler exists. **Fix:** remove `cursor:pointer` or wire them.

### m31. Stale scaffold comments and a dead drifted example block
`Bridge.swift:9-12` ("Phase 1 scaffold... unhandled commands are logged" — both false now); `Protocol.swift:448-467` (20-line commented-out FiddleBridge example that has drifted from the real class); `Permissions.swift:6-7` ("Phase 2 recorder" — shipped). **Fix:** update/delete.

---

## What's solid

Verified clean by the scouts and re-confirmed where load-bearing:

- **Tap self-healing:** both taps re-enable on `tapDisabledByTimeout`/`tapDisabledByUserInput` (`ClickRecorder.swift:45-51`, `PositionPicker.swift:33-39`), and the `Unmanaged.passUnretained` callback pattern is safe because both objects live for the app's lifetime via FiddleController.
- **Power assertions:** `PowerAssertion` acquire/release is idempotent with a `deinit` guard; every assertion-holding engine releases on stop, `start()` always stops first, and `applicationWillTerminate` → `shutdown()` covers quit. No leak path found, including profile-apply while running.
- **ClickEngine double-click synthesis:** clickState set on down and up of each pair, singles reset to 1 (`ClickEngine.swift:90-107`).
- **Coordinate spaces:** picker → store → click path stays in Quartz global coordinates end to end, correct on multi-display setups with negative origins; the AppKit-to-Quartz flip in `pointInsideAppWindow` is mathematically right.
- **ClickEngine/KeyEngine timing and stop safety:** zero-leeway `DispatchSourceTimer` on dedicated queues (not main-runloop `Timer`), `queue.sync` stop that drains in-flight ticks, per-run timers immune to the restart race that afflicts PlaybackEngine.
- **KeyEngine key hygiene:** down/up posted back to back with explicit flags on both; no stuck-key or modifier-leak path.
- **Bridge transport:** Swift-to-JS payloads are whole-Event JSON-encoded (no string interpolation of fields); JS-to-Swift goes through typed `JSONDecoder` with unknown types throwing and a per-surface error reply; the `WeakScriptMessageHandler` proxy breaks the classic WKUserContentController retain cycle on both surfaces.
- **Engine input clamping:** intervals clamped to ≥1 in every engine plus independent JS clamps; zero/negative payloads cannot produce a runaway timer.
- **Settings migration:** lenient `decodeIfPresent` initializers across all persisted types, regression-tested against legacy blobs in `SettingsTests`; unknown/wrong-typed `setPref` keys ignored before save.
- **Hygiene:** no TODO/FIXME/HACK markers, no `try!`/`as!` anywhere, no localStorage in the skin, clean two-key UserDefaults namespace, `loadFileURL` correctly scoped to the bundled web directory with no remote content.
- **Panic execution context:** the panic handler runs on the main thread via Carbon hotkey delivery; no engine `stop()` can block it (the gaps are C2's missing recorder stop and C3's rebind fragility, not dispatch).

## Prioritized fix order

1. **C2 — panic/stopAll must stop the recorder tap.** The panic key is the product's safety contract; one-line change to `stopEngines()`/`panic()` plus the endRecording bookkeeping.
2. **C1 — post compensating mouse-up on playback abort.** The other half of the panic contract: panic must never leave a button held. Small, contained fix in `playLoop`.
3. **C3 — reject duplicate hotkey combos.** Prevents the panic binding from being shadowed or silently destroyed; a four-way comparison in `setHotkey`.
4. **M1 — generation token in PlaybackEngine.** Eliminates the double-posting/dead-run race that every stop-start cycle flirts with, and the stuck-Running fallout.
5. **M7 — setStatus(.idle) after stopEngines() in start().** One line that fixes a whole family of stuck-Running states (and subsumes m11's variant).

Close behind: M8 (persist() in four views plus the unreachable recorder config) and M6 (rebroadcast config/prefs) — the two most user-visible correctness gaps outside the panic path.
