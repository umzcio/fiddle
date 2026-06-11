# Follow-ups from the code-review remediation pass

Items intentionally not fixed on the `code-review-fixes` branch: deferred
findings that need a design decision, plus adjacent problems spotted during
surgery but outside the findings being fixed.

## Deferred findings (need an owner decision)

- **m18 — Recorder does not capture drags.** Feature work, not a surgical fix.
  Sketch: add `leftMouseDragged` / `rightMouseDragged` / `otherMouseDragged`
  to the tap mask, coalesce moves (at most one per ~16ms or 4px delta),
  record them as `.move`, and teach the playback poster to emit per-button
  dragged events for moves occurring between a down and its up (it currently
  emits only `.mouseMoved`, the wrong type mid-drag). Interacts with the m1
  10,000-event cap, since drags generate hundreds of events per second; the
  cap policy needs revisiting alongside this.

- **m24 — AntiAFKEngine duplicates JiggleEngine.** Structural refactor.
  Sketch: `AntiAFKEngine.start` maps `AntiAFKConfig` to
  `JigglerConfig(intervalSec:distancePx:mode:.visible, keepAwake:, idleOnly:false)`
  and delegates to an owned `JiggleEngine`, keeping its own assertion reason
  string. Removes the duplicated timer/nudge/direction logic.

- **m25 — ClickEngine/KeyEngine boilerplate duplication.** Structural
  refactor. Sketch: extract a generic repeating-timer engine
  (zero-leeway `DispatchSourceTimer` + run state + main-actor onFinished
  marshal) parameterized by a per-tick closure; merge
  `ClickRunState.recordClick` / `KeyRunState.recordPress` into one
  `RepeatRunState`. Touches the m8/m9 synchronization fixes, so it should be
  done as its own reviewed change.

- **m26 — ClickRecorder/PositionPicker tap boilerplate duplication.**
  Structural refactor of C-callback lifetime code. Sketch: a `ListenOnlyTap`
  helper owning tapCreate / runloop source / timeout re-enable / teardown,
  with an event mask and a Swift callback; the `Unmanaged` refcon pattern
  then lives in exactly one place.

- **m27 — Duplicated JS key-capture logic.** Deliberately deferred: the m3
  fix makes the two capture flows' validation rules intentionally different
  (global hotkeys now require a modifier; the keyboard auto-presser capture
  must keep accepting bare keys). A shared `captureCombo(btn, validate,
  onDone)` helper is still worthwhile but needs that validation parameter
  designed in.

## Partial-fix notes

- **m1 (recording cap):** the cap is in; the second half of the suggested
  fix, moving the recording out of the `fiddle.settings.v1` blob into its
  own storage key or file, is a schema migration and is not done. The cap
  bounds the problem meanwhile.

## Adjacent issues spotted (not in the review findings)

- **PositionPicker can capture fiddle's own synthesized click as the pick.**
  While fixing M3, the recorder tap gained a synthetic-event filter
  (`SyntheticEvents.userDataTag`), but `PositionPicker`'s tap does not check
  it. If the clicker is running when the user starts a position pick, a
  synthesized click can satisfy the pick instead of the user's. Same one-line
  filter as ClickRecorder would fix it; left untouched because the finding
  covered only the recorder.
