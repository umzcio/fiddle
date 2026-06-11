//
//  FiddleController.swift
//  Fiddle
//
//  The coordinator that sits between the bridge and the engine layer. It owns the
//  engines, permissions, hotkeys, position picker, and settings; it routes inbound
//  Commands and emits outbound Events. This is the one place that knows about both
//  the web side (Events) and the engine side, keeping the engines UI-agnostic.
//

import AppKit
import os

/// Anything that can deliver an Event to the web UI (implemented by the bridge).
@MainActor
protocol EngineEventSink: AnyObject {
    func emit(_ event: Event)
}

@MainActor
final class FiddleController {
    private struct WeakSink { weak var sink: EngineEventSink? }
    private var sinks: [WeakSink] = []

    /// Register a web client to receive Events. Held weakly.
    func addSink(_ sink: EngineEventSink) {
        sinks.removeAll { $0.sink == nil }
        if !sinks.contains(where: { $0.sink === sink }) {
            sinks.append(WeakSink(sink: sink))
        }
    }

    private func broadcast(_ event: Event) {
        sinks.removeAll { $0.sink == nil }
        for entry in sinks { entry.sink?.emit(event) }
    }

    /// Broadcast to every sink except the one a command originated from, so
    /// the other surface syncs without re-rendering the form being edited.
    private func broadcast(_ event: Event, excluding excluded: EngineEventSink?) {
        sinks.removeAll { $0.sink == nil }
        for entry in sinks where entry.sink !== excluded { entry.sink?.emit(event) }
    }

    /// Deliver to one sink when known, otherwise to everyone.
    private func send(_ event: Event, to sink: EngineEventSink?) {
        if let sink { sink.emit(event) } else { broadcast(event) }
    }

    let store: SettingsStore
    private let permissions = PermissionsManager()
    private let clickEngine = ClickEngine()
    private let jiggleEngine = JiggleEngine()
    private let wakeLockEngine = WakeLockEngine()
    private let antiAFKEngine = AntiAFKEngine()
    private let clickRecorder = ClickRecorder()
    private let playbackEngine = PlaybackEngine()
    private let keyEngine = KeyEngine()
    private let hotkeys = HotkeyManager()
    private let picker = PositionPicker()
    private let clickSound = ClickSound()
    private let log = Logger(subsystem: "edu.umontana.fiddle", category: "controller")

    private var status: RunStatus = .idle
    private var lastMode: AutomationMode = .clicker
    private var pickPurpose: String?

    /// The menu-bar icon observes this for the running state.
    var menuState: MenuState? {
        didSet { menuState?.status = status; menuState?.skin = store.settings.prefs.skin }
    }

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        // The !isRunning guard drops stale completions: a bounded run's
        // finished Task can land on the main actor after a stop+restart of the
        // same mode, and must not flip the fresh run's status to idle.
        clickEngine.onFinished    = { [weak self] in guard let self, self.lastMode == .clicker, !self.clickEngine.isRunning else { return }; self.setStatus(.idle) }
        picker.onPicked = { [weak self] x, y in self?.handlePicked(x: x, y: y) }
        playbackEngine.onFinished = { [weak self] in guard let self, self.lastMode == .recorder || self.lastMode == .macro, !self.playbackEngine.isRunning else { return }; self.setStatus(.idle) }
        keyEngine.onFinished      = { [weak self] in guard let self, self.lastMode == .keyboard, !self.keyEngine.isRunning else { return }; self.setStatus(.idle) }
        clickRecorder.exclude = { [weak self] point in self?.pointInsideAppWindow(point) ?? false }
        clickRecorder.onLimitReached = { [weak self] in
            guard let self else { return }
            self.endRecording()
            self.broadcast(.error(message: "Recording stopped: the \(ClickRecorder.maxEvents)-step limit was reached."))
        }
        configureHotkeys()
        applyStartupPrefs()
    }

    /// Apply persisted prefs at launch (login-item state is owned by macOS, so
    /// it is not forced here; the dock/menu-bar policy and sound hook are).
    private func applyStartupPrefs() {
        NSApp.setActivationPolicy(store.settings.prefs.menuBarOnly ? .accessory : .regular)
        updateClickSoundHook()
    }

    private func updateClickSoundHook() {
        if store.settings.prefs.soundOnClick {
            clickEngine.setOnClick { [weak self] in self?.clickSound.play() }
        } else {
            clickEngine.setOnClick(nil)
        }
    }

    // MARK: - Command routing

    func handle(_ command: Command, from sink: EngineEventSink? = nil) {
        switch command {
        case .ready:                          pushInitialState(to: sink)
        case .checkPermissions:               emitPermissions()
        case .openSettings(let pane):         openSettings(pane)
        case .start(let mode, let config):    start(mode: mode, config: config)
        case .stop:                           stopAll()
        case .updateConfig(let mode, let config):
            // Persist AND sync the other live surface (main window or menu-bar
            // popover); otherwise its stale form state overwrites this edit on
            // its next start.
            if saveConfig(mode: mode, config: config) {
                broadcast(.config(mode: mode, config: config), excluding: sink)
            }
        case .pickPosition(let purpose):      beginPick(purpose: purpose)
        case .setHotkey(let action, let combo): setHotkey(action: action, combo: combo)
        case .setPref(let key, let value):
            applyPref(key: key, value: value)
            broadcast(prefsEvent(), excluding: sink)
        case .window:                         break  // handled by the window host
        case .recordStart:                    beginRecording()
        case .recordStop:                     endRecording()
        case .clearRecording:                 clearRecording()
        case .saveMacros(let macros):         saveMacros(macros)
        case .saveProfiles(let profiles):     saveProfiles(profiles)
        case .applyProfile(let id):           applyProfile(id)
        }
    }

    private func applyPref(key: String, value: PrefValue) {
        store.setPref(key, value)
        switch (key, value) {
        case ("launchAtLogin", .bool(let b)):
            if !LoginItem.setEnabled(b) {
                if b && LoginItem.requiresApproval {
                    broadcast(.error(message: "macOS needs your approval: enable fiddle under Login Items in System Settings."))
                    LoginItem.openSystemSettings()
                } else {
                    broadcast(.error(message: "The login item could not be \(b ? "enabled" : "disabled")."))
                }
                // Correct every surface's toggle, including the sender's.
                broadcast(prefsEvent())
            }
        case ("menuBarOnly", .bool(let b)):   NSApp.setActivationPolicy(b ? .accessory : .regular)
        case ("soundOnClick", _):             updateClickSoundHook()
        case ("skin", .string(let s)):        menuState?.skin = s
        default: break
        }
    }

    // MARK: - Start / stop

    /// Stop every engine without touching the run status. Callers are
    /// responsible for updating status afterwards if needed.
    private func stopEngines() {
        clickEngine.stop(); jiggleEngine.stop(); wakeLockEngine.stop()
        antiAFKEngine.stop(); playbackEngine.stop(); keyEngine.stop()
    }

    private func start(mode: AutomationMode, config: Config) {
        // Never run engines while the recorder tap is armed: even with
        // synthesized events tagged and filtered, a recording session mixing
        // live engine output makes no sense. End and persist it first.
        if clickRecorder.isRecording { endRecording() }
        saveConfig(mode: mode, config: config)
        stopEngines()
        // Everything is stopped now; say so before the guards below can bail.
        // Without this, an early return (permission denied, empty recording,
        // missing macro) leaves the LED and toggleStartStop stuck on Running
        // with nothing running.
        setStatus(.idle)
        switch mode {
        case .clicker:
            // Posting synthetic clicks requires Accessibility.
            guard permissions.accessibilityTrusted(promptIfNeeded: true) else {
                emitPermissions()
                broadcast(.error(message: "Accessibility permission is required to click."))
                return
            }
            guard case .clicker(let clickerConfig) = config else { return }
            if clickerConfig.position == .fixed,
               !Self.pointsWithinDisplays([CGPoint(x: clickerConfig.x, y: clickerConfig.y)]) {
                broadcast(.error(message: "The saved fixed position is outside the connected displays. Pick it again."))
                return
            }
            clickEngine.start(config: clickerConfig)
            lastMode = .clicker
            setStatus(.running)
        case .jiggler:
            guard case .jiggler(let jigglerConfig) = config else { return }
            jiggleEngine.start(config: jigglerConfig)
            lastMode = .jiggler
            setStatus(.running)
        case .wakeLock:
            guard case .wakeLock(let wl) = config else { return }
            // Both toggles off would show Running while holding no assertion.
            guard wl.keepDisplayAwake || wl.keepSystemAwake else {
                broadcast(.error(message: "Turn on at least one wake option first."))
                return
            }
            wakeLockEngine.start(config: wl)
            lastMode = .wakeLock
            setStatus(.running)
        case .antiAFK:
            guard case .antiAFK(let a) = config else { return }
            antiAFKEngine.start(config: a)
            lastMode = .antiAFK
            setStatus(.running)
        case .recorder:
            // Playback synthesizes clicks, so it needs Accessibility too.
            guard permissions.accessibilityTrusted(promptIfNeeded: true) else {
                emitPermissions()
                broadcast(.error(message: "Accessibility permission is required to play a recording."))
                return
            }
            guard case .recorder(let recorderConfig) = config else { return }
            let events = store.settings.recording
            guard !events.isEmpty else {
                broadcast(.error(message: "Record some clicks before playing."))
                return
            }
            guard Self.pointsWithinDisplays(events.map { CGPoint(x: $0.x, y: $0.y) }) else {
                broadcast(.error(message: "This recording was made on a different display arrangement. Record it again."))
                return
            }
            playbackEngine.start(events: events, config: recorderConfig)
            lastMode = .recorder
            setStatus(.running)
        case .macro:
            guard permissions.accessibilityTrusted(promptIfNeeded: true) else {
                emitPermissions()
                broadcast(.error(message: "Accessibility permission is required to play a macro."))
                return
            }
            guard case .macro(let macroConfig) = config else { return }
            guard let macro = store.settings.macros.first(where: { $0.id == macroConfig.macroId }) else {
                broadcast(.error(message: "That macro was not found."))
                return
            }
            let events = MacroCompiler.compile(macro.steps)
            guard !events.isEmpty else {
                broadcast(.error(message: "That macro has no steps to play."))
                return
            }
            guard Self.pointsWithinDisplays(events.map { CGPoint(x: $0.x, y: $0.y) }) else {
                broadcast(.error(message: "That macro clicks outside the connected displays."))
                return
            }
            playbackEngine.start(events: events, config: RecorderConfig(repeat: macroConfig.repeat, times: macroConfig.times))
            lastMode = .macro
            setStatus(.running)
        case .keyboard:
            guard permissions.accessibilityTrusted(promptIfNeeded: true) else {
                emitPermissions()
                broadcast(.error(message: "Accessibility permission is required to press keys."))
                return
            }
            guard case .keyboard(let kb) = config else { return }
            guard let shortcut = HotkeyCombo.parse(kb.combo) else {
                broadcast(.error(message: "Pick a key to press first."))
                return
            }
            keyEngine.start(keyCode: CGKeyCode(shortcut.carbonKeyCode),
                            flags: KeyboardSynthesis.flags(from: shortcut.modifiers),
                            intervalMs: kb.intervalMs, repeat: kb.repeat, times: kb.times)
            lastMode = .keyboard
            setStatus(.running)
        }
    }

    private func stopAll() {
        // The recorder's tap is not an "engine", but stop and panic must halt
        // it too; otherwise the system-wide tap keeps capturing after a panic.
        if clickRecorder.isRecording { endRecording() }
        stopEngines()
        setStatus(.idle)
    }

    /// Start the last-used mode, or stop if already running. Used by the menu bar.
    func toggleStartStop() {
        if status == .running {
            stopAll()
        } else {
            start(mode: lastMode, config: config(for: lastMode))
        }
    }

    private func setStatus(_ newStatus: RunStatus) {
        if newStatus == .running && status != .running {
            logActivity("Started \(Self.modeLabel(lastMode))")
        } else if newStatus == .idle && status == .running {
            logActivity("Stopped")
        }
        status = newStatus
        menuState?.status = newStatus
        broadcast(.status(newStatus))
    }

    // MARK: - Hotkeys

    private func configureHotkeys() {
        hotkeys.onStartStop = { [weak self] in self?.hotkeyStartStop() }
        hotkeys.onToggleJiggler = { [weak self] in self?.hotkeyToggleJiggler() }
        hotkeys.onPickPosition = { [weak self] in self?.beginPick() }
        hotkeys.onPanic = { [weak self] in self?.panic() }
        hotkeys.register()
    }

    private func setHotkey(action: HotkeyAction, combo: String) {
        guard let shortcut = HotkeyCombo.parse(combo) else {
            broadcast(.error(message: "That key combination is not supported."))
            emitHotkeys()   // revert the keycap to the real binding
            return
        }
        guard HotkeyCombo.isAcceptableGlobalHotkey(shortcut) else {
            broadcast(.error(message: "Add a modifier key (or use a function key); a bare key would stop working in every app."))
            emitHotkeys()
            return
        }
        // Refuse a combo already bound to another action. The package fires
        // every matching handler on one press, and a later rebind of either
        // action unregisters the shared Carbon hotkey out from under the
        // other; worst case the panic key dies until relaunch.
        let allActions: [HotkeyAction] = [.startStop, .toggleJiggler, .pickPosition, .panic]
        if let taken = allActions.first(where: { $0 != action && hotkeys.shortcut(for: $0) == shortcut }) {
            broadcast(.error(message: "That key is already bound to \(Self.hotkeyLabel(taken))."))
            emitHotkeys()
            return
        }
        hotkeys.setShortcut(shortcut, for: action)
        emitHotkeys()
    }

    private static func hotkeyLabel(_ action: HotkeyAction) -> String {
        switch action {
        case .startStop:     return "Start / Stop"
        case .toggleJiggler: return "Toggle Jiggler"
        case .pickPosition:  return "Pick Position"
        case .panic:         return "Panic"
        }
    }

    /// Push the current bindings so the web keycaps reflect persisted state.
    private func emitHotkeys(to sink: EngineEventSink? = nil) {
        let actions: [HotkeyAction] = [.startStop, .toggleJiggler, .pickPosition, .panic]
        var bindings: [String: String] = [:]
        for action in actions {
            if let shortcut = hotkeys.shortcut(for: action),
               let token = HotkeyCombo.string(from: shortcut) {
                bindings[action.rawValue] = token
            }
        }
        send(.hotkeys(bindings: bindings), to: sink)
    }

    private func hotkeyStartStop() {
        broadcast(.hotkeyTriggered(action: .startStop))
        toggleStartStop()
    }

    private func hotkeyToggleJiggler() {
        broadcast(.hotkeyTriggered(action: .toggleJiggler))
        if status == .running && lastMode == .jiggler {
            stopAll()
        } else {
            start(mode: .jiggler, config: config(for: .jiggler))
        }
    }

    private func panic() {
        stopAll()
        logActivity("Panic: all automation halted", level: "warn")
        picker.cancel()
        broadcast(.hotkeyTriggered(action: .panic))
    }

    // MARK: - Position picker

    private func beginPick(purpose: String? = nil) {
        guard permissions.accessibilityTrusted(promptIfNeeded: true) else {
            emitPermissions()
            return
        }
        pickPurpose = purpose
        picker.begin()
        // Tap creation can fail (permission granted mid-session takes effect
        // at relaunch); the form is already waiting for positionPicked, so
        // never leave it hanging silently.
        guard picker.isPicking else {
            pickPurpose = nil
            broadcast(.error(message: "Position picking could not start. If you just changed permissions, quit and relaunch fiddle."))
            return
        }
    }

    private func handlePicked(x: Int, y: Int) {
        if pickPurpose != "step" {
            var clicker = store.settings.clicker
            clicker.x = x
            clicker.y = y
            clicker.position = .fixed
            store.setClicker(clicker)
        }
        pickPurpose = nil
        broadcast(.positionPicked(x: x, y: y))
        logActivity("Position picked (\(x), \(y))")
    }

    // MARK: - Permissions

    private func emitPermissions(to sink: EngineEventSink? = nil) {
        send(.permissions(
            accessibility: permissions.accessibilityTrusted(),
            inputMonitoring: permissions.inputMonitoringGranted()
        ), to: sink)
    }

    /// Re-poll permission state and update the UI. Called when the app regains
    /// focus, since the user may have just toggled access in System Settings.
    func recheckPermissions() {
        emitPermissions()
        // Engines that post events silently no-op once Accessibility is
        // revoked: the timer keeps firing and the LED shows Running while
        // nothing happens. Stop honestly instead.
        let postsEvents: Set<AutomationMode> = [.clicker, .recorder, .macro, .keyboard]
        if status == .running, postsEvents.contains(lastMode), !permissions.accessibilityTrusted() {
            stopAll()
            broadcast(.error(message: "Accessibility permission was revoked, so automation was stopped."))
        }
    }

    private func openSettings(_ pane: SettingsPane) {
        switch pane {
        case .accessibility:   permissions.openAccessibilitySettings()
        case .inputMonitoring: permissions.openInputMonitoringSettings()
        }
    }

    // MARK: - Settings

    /// Push the full saved state. Scoped to the surface whose `ready` asked for
    /// it; one surface booting must not re-render (and re-fit) the other.
    private func pushInitialState(to sink: EngineEventSink? = nil) {
        send(.config(mode: .clicker, config: .clicker(store.settings.clicker)), to: sink)
        send(.config(mode: .jiggler, config: .jiggler(store.settings.jiggler)), to: sink)
        send(.config(mode: .wakeLock, config: .wakeLock(store.settings.wakeLock)), to: sink)
        send(.config(mode: .antiAFK, config: .antiAFK(store.settings.antiAFK)), to: sink)
        send(.config(mode: .recorder, config: .recorder(store.settings.recorder)), to: sink)
        send(.config(mode: .keyboard, config: .keyboard(store.settings.keyboard)), to: sink)
        emitPermissions(to: sink)
        send(prefsEvent(), to: sink)
        emitHotkeys(to: sink)
        emitRecording(to: sink)
        emitMacros(to: sink)
        emitProfiles(to: sink)
        if store.didResetToDefaults {
            store.acknowledgeReset()
            send(.error(message: "Saved settings could not be read and were reset to defaults. The unreadable data is kept under the fiddle.settings.v1.backup defaults key."), to: sink)
        }
    }

    /// Persist a config edit. Returns false when the (mode, config) shapes do
    /// not match and nothing was saved.
    @discardableResult
    private func saveConfig(mode: AutomationMode, config: Config) -> Bool {
        switch (mode, config) {
        case (.clicker, .clicker(let clickerConfig)): store.setClicker(clickerConfig)
        case (.jiggler, .jiggler(let jigglerConfig)): store.setJiggler(jigglerConfig)
        case (.wakeLock, .wakeLock(let wl)): store.setWakeLock(wl)
        case (.antiAFK, .antiAFK(let a)):    store.setAntiAFK(a)
        case (.recorder, .recorder(let rc)): store.setRecorder(rc)
        case (.keyboard, .keyboard(let kb)): store.setKeyboard(kb)
        default: return false
        }
        return true
    }

    /// The current prefs as a single Event, the same shape every prefs push
    /// uses (initial state, profile apply, live pref edits).
    private func prefsEvent() -> Event {
        let p = store.settings.prefs
        return .prefs(launchAtLogin: LoginItem.isEnabled, menuBarOnly: p.menuBarOnly, soundOnClick: p.soundOnClick, skin: p.skin, device: p.device, interfaceMode: p.interfaceMode)
    }

    private func config(for mode: AutomationMode) -> Config {
        switch mode {
        case .clicker:  return .clicker(store.settings.clicker)
        case .jiggler:  return .jiggler(store.settings.jiggler)
        case .wakeLock: return .wakeLock(store.settings.wakeLock)
        case .antiAFK:  return .antiAFK(store.settings.antiAFK)
        case .recorder: return .recorder(store.settings.recorder)
        case .macro:    return .macro(MacroConfig(macroId: "", repeat: .until, times: 1))
        case .keyboard: return .keyboard(store.settings.keyboard)
        }
    }

    /// Force-stop everything, e.g. on app termination.
    func shutdown() {
        stopEngines()
        clickRecorder.stop()
        picker.cancel()
    }

    // MARK: - Recorder

    private func beginRecording() {
        guard permissions.inputMonitoringGranted() else {
            permissions.requestInputMonitoring()
            emitPermissions()
            broadcast(.error(message: "Input Monitoring permission is required to record. Grant it in System Settings, then relaunch."))
            return
        }
        // Stopping a running engine here must go through stopAll so the run
        // status follows; a bare engine stop leaves the LED stuck on Running.
        if status == .running {
            stopAll()
        } else {
            playbackEngine.stop()
        }
        clickRecorder.start()
        // Tap creation can fail even with the permission reported granted
        // (granting Input Monitoring mid-session takes effect at relaunch).
        // Never tell the UI a recording is active when no tap exists.
        guard clickRecorder.isRecording else {
            broadcast(.error(message: "Recording could not start. If you just granted Input Monitoring, quit and relaunch fiddle."))
            emitRecording()
            return
        }
        broadcast(.recording(active: true, steps: RecordedSequence.displaySteps(store.settings.recording)))
    }

    private func endRecording() {
        let events = clickRecorder.stop()
        store.setRecording(events)
        logActivity("Recording saved (\(events.count) steps)")
        emitRecording()
    }

    private func clearRecording() {
        clickRecorder.stop()
        store.setRecording([])
        emitRecording()
    }

    private func emitRecording(to sink: EngineEventSink? = nil) {
        send(.recording(active: false, steps: RecordedSequence.displaySteps(store.settings.recording)), to: sink)
    }

    // MARK: - Macros

    private func saveMacros(_ macros: [Macro]) {
        store.setMacros(macros)
        emitMacros()
    }

    private func emitMacros(to sink: EngineEventSink? = nil) {
        send(.macros(list: store.settings.macros), to: sink)
    }

    // MARK: - Profiles

    private func saveProfiles(_ profiles: [Profile]) {
        store.setProfiles(profiles)
        emitProfiles()
    }

    private func emitProfiles(to sink: EngineEventSink? = nil) {
        send(.profiles(list: store.settings.profiles), to: sink)
    }

    private func applyProfile(_ id: String) {
        guard let p = store.settings.profiles.first(where: { $0.id == id }) else {
            broadcast(.error(message: "That profile was not found."))
            return
        }
        store.update { settings in
            settings.clicker = p.clicker
            settings.jiggler = p.jiggler
            settings.wakeLock = p.wakeLock
            settings.antiAFK = p.antiAFK
            settings.keyboard = p.keyboard
            settings.prefs.device = p.device
        }
        // Re-push so the UI reflects the applied profile.
        broadcast(.config(mode: .clicker, config: .clicker(p.clicker)))
        broadcast(.config(mode: .jiggler, config: .jiggler(p.jiggler)))
        broadcast(.config(mode: .wakeLock, config: .wakeLock(p.wakeLock)))
        broadcast(.config(mode: .antiAFK, config: .antiAFK(p.antiAFK)))
        broadcast(.config(mode: .keyboard, config: .keyboard(p.keyboard)))
        broadcast(prefsEvent())
        logActivity("Applied profile \(p.name)")
    }

    // MARK: - Activity

    private func logActivity(_ message: String, level: String = "info") {
        broadcast(.log(message: message, level: level))
    }

    static func modeLabel(_ mode: AutomationMode) -> String {
        switch mode {
        case .clicker:  return "Auto Clicker"
        case .jiggler:  return "Mouse Jiggler"
        case .wakeLock: return "Wake Lock"
        case .antiAFK:  return "Anti-AFK"
        case .recorder: return "Recording playback"
        case .macro:    return "Macro"
        case .keyboard: return "Auto Presser"
        }
    }

    /// Whether every Quartz-global point lands on a connected display. Posting
    /// an off-screen point gets pinned to a display edge by the WindowServer
    /// and clicks whatever UI lives there, so stale multi-display recordings
    /// and fixed positions are refused instead.
    private static func pointsWithinDisplays(_ points: [CGPoint]) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let maxY = primary.frame.maxY
        // AppKit frames are bottom-left global; flip to Quartz top-left. The
        // 1pt outset tolerates cursor coordinates rounded onto the edge.
        let quartzFrames = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: maxY - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
                .insetBy(dx: -1, dy: -1)
        }
        return points.allSatisfy { point in quartzFrames.contains { $0.contains(point) } }
    }

    /// Is the Quartz point over one of fiddle's own windows, z-order aware?
    /// Used to drop the user's own Record/Stop clicks from the recording.
    /// Pure frame containment would also exclude clicks on OTHER apps'
    /// windows stacked in front of fiddle's, silently losing recorded steps,
    /// so the topmost on-screen window at the point decides.
    private func pointInsideAppWindow(_ point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let myPid = pid_t(ProcessInfo.processInfo.processIdentifier)
        for info in list {   // front-to-back order; bounds are Quartz global
            guard
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                bounds.contains(point)
            else { continue }
            return (info[kCGWindowOwnerPID as String] as? pid_t) == myPid
        }
        return false
    }
}
