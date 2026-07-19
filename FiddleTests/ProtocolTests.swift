import XCTest
@testable import Fiddle

final class ProtocolTests: XCTestCase {

    private func object(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    func testDecodeStartClickerCommand() throws {
        let json = """
        {"type":"start","mode":"clicker","config":{"intervalMs":250,"button":"right","clickType":"double","repeat":"times","times":5,"position":"fixed","x":10,"y":20}}
        """
        let command = try Bridge.decodeCommand(from: try object(json))
        guard case .start(let mode, let config) = command,
              mode == .clicker,
              case .clicker(let clicker) = config else {
            return XCTFail("expected a clicker start command")
        }
        XCTAssertEqual(clicker.intervalMs, 250)
        XCTAssertEqual(clicker.button, .right)
        XCTAssertEqual(clicker.clickType, .double)
        XCTAssertEqual(clicker.repeat, .times)
        XCTAssertEqual(clicker.times, 5)
        XCTAssertEqual(clicker.position, .fixed)
        XCTAssertEqual(clicker.x, 10)
        XCTAssertEqual(clicker.y, 20)
    }

    func testDecodeWindowCommand() throws {
        let command = try Bridge.decodeCommand(from: try object(#"{"type":"window","action":"close"}"#))
        guard case .window(let action) = command else { return XCTFail("expected window command") }
        XCTAssertEqual(action, .close)
    }

    func testEncodeConfigEventCarriesModeAndConfig() throws {
        let clicker = ClickerConfig(intervalMs: 100, button: .left, clickType: .single,
                                    repeat: .until, times: 50, position: .current, x: 1, y: 2)
        let js = try Bridge.script(for: .config(mode: .clicker, config: .clicker(clicker)))
        XCTAssertTrue(js.hasPrefix("window.fiddleEvent("))
        XCTAssertTrue(js.contains("\"type\":\"config\""))
        XCTAssertTrue(js.contains("\"mode\":\"clicker\""))
        XCTAssertTrue(js.contains("\"intervalMs\":100"))
    }

    func testEncodeStatusEvent() throws {
        let js = try Bridge.script(for: .status(.running))
        XCTAssertTrue(js.contains("\"type\":\"status\""))
        XCTAssertTrue(js.contains("\"value\":\"running\""))
    }

    func testEncodePrefsEvent() throws {
        let js = try Bridge.script(for: .prefs(launchAtLogin: true, menuBarOnly: false, soundOnClick: true, skin: "cobalt", device: "keyboard", interfaceMode: "simple", lastMode: "jiggler"))
        XCTAssertTrue(js.contains("\"type\":\"prefs\""))
        XCTAssertTrue(js.contains("\"launchAtLogin\":true"))
        XCTAssertTrue(js.contains("\"menuBarOnly\":false"))
        XCTAssertTrue(js.contains("\"soundOnClick\":true"))
        XCTAssertTrue(js.contains("\"skin\":\"cobalt\""))
        XCTAssertTrue(js.contains("\"device\":\"keyboard\""))
        XCTAssertTrue(js.contains("\"interfaceMode\":\"simple\""))
        XCTAssertTrue(js.contains("\"lastMode\":\"jiggler\""))
    }

    func testDecodeWindowFit() throws {
        guard case .window(let action) = try Bridge.decodeCommand(from: try object(#"{"type":"window","action":"fit"}"#)) else { return XCTFail() }
        XCTAssertEqual(action, .fit)
    }

    func testDecodeSetPrefCommand() throws {
        let cmd = try Bridge.decodeCommand(from: try object(#"{"type":"setPref","key":"soundOnClick","value":true}"#))
        guard case .setPref(let key, let value) = cmd else { return XCTFail("expected setPref") }
        XCTAssertEqual(key, "soundOnClick")
        XCTAssertEqual(value, .bool(true))
    }

    func testDecodeStartWakeLock() throws {
        let cmd = try Bridge.decodeCommand(from: try object(#"{"type":"start","mode":"wakeLock","config":{"keepDisplayAwake":true,"keepSystemAwake":false}}"#))
        guard case .start(let mode, let config) = cmd, mode == .wakeLock, case .wakeLock(let wl) = config else { return XCTFail() }
        XCTAssertTrue(wl.keepDisplayAwake); XCTAssertFalse(wl.keepSystemAwake)
    }

    func testDecodeStartAntiAFK() throws {
        let cmd = try Bridge.decodeCommand(from: try object(#"{"type":"start","mode":"antiAFK","config":{"intervalSec":45,"distancePx":25,"keepAwake":true}}"#))
        guard case .start(let mode, let config) = cmd, mode == .antiAFK, case .antiAFK(let a) = config else { return XCTFail() }
        XCTAssertEqual(a.intervalSec, 45); XCTAssertEqual(a.distancePx, 25); XCTAssertTrue(a.keepAwake)
    }

    func testEncodeConfigEventForWakeLockAndAntiAFK() throws {
        let js1 = try Bridge.script(for: .config(mode: .wakeLock, config: .wakeLock(WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: true))))
        XCTAssertTrue(js1.contains("\"mode\":\"wakeLock\"")); XCTAssertTrue(js1.contains("\"keepSystemAwake\":true"))
        let js2 = try Bridge.script(for: .config(mode: .antiAFK, config: .antiAFK(AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true))))
        XCTAssertTrue(js2.contains("\"mode\":\"antiAFK\"")); XCTAssertTrue(js2.contains("\"intervalSec\":60"))
    }

    func testDecodeWindowShowAndQuit() throws {
        guard case .window(let a) = try Bridge.decodeCommand(from: try object(#"{"type":"window","action":"showWindow"}"#)), a == .showWindow else { return XCTFail("showWindow") }
        guard case .window(let b) = try Bridge.decodeCommand(from: try object(#"{"type":"window","action":"quit"}"#)), b == .quit else { return XCTFail("quit") }
    }

    func testDecodeRecordCommands() throws {
        guard case .recordStart = try Bridge.decodeCommand(from: try object(#"{"type":"recordStart"}"#)) else { return XCTFail("recordStart") }
        guard case .recordStop = try Bridge.decodeCommand(from: try object(#"{"type":"recordStop"}"#)) else { return XCTFail("recordStop") }
        guard case .clearRecording = try Bridge.decodeCommand(from: try object(#"{"type":"clearRecording"}"#)) else { return XCTFail("clearRecording") }
    }

    func testDecodeResetHotkeysCommand() throws {
        guard case .resetHotkeys = try Bridge.decodeCommand(from: try object(#"{"type":"resetHotkeys"}"#)) else { return XCTFail("resetHotkeys") }
    }

    func testDecodeStartRecorderCommand() throws {
        let cmd = try Bridge.decodeCommand(from: try object(#"{"type":"start","mode":"recorder","config":{"repeat":"times","times":4}}"#))
        guard case .start(let mode, let config) = cmd, mode == .recorder, case .recorder(let cfg) = config else {
            return XCTFail("expected start recorder")
        }
        XCTAssertEqual(cfg.times, 4)
        XCTAssertEqual(cfg.repeat, .times)
    }

    func testEncodeRecordingEvent() throws {
        let js = try Bridge.script(for: .recording(active: false, steps: [DisplayStep(label: "Left click", x: 5, y: 6, delayMs: 0)]))
        XCTAssertTrue(js.contains("\"type\":\"recording\""))
        XCTAssertTrue(js.contains("\"active\":false"))
        XCTAssertTrue(js.contains("\"label\":\"Left click\""))
    }

    func testDecodePickPositionPurpose() throws {
        guard case .pickPosition(let p1) = try Bridge.decodeCommand(from: try object(#"{"type":"pickPosition"}"#)) else { return XCTFail() }
        XCTAssertNil(p1)
        guard case .pickPosition(let p2) = try Bridge.decodeCommand(from: try object(#"{"type":"pickPosition","purpose":"step"}"#)) else { return XCTFail() }
        XCTAssertEqual(p2, "step")
    }

    func testDecodeSaveMacros() throws {
        let json = #"{"type":"saveMacros","macros":[{"id":"m1","name":"A","steps":[{"kind":"wait","button":"left","clickType":"single","x":0,"y":0,"ms":100}]}]}"#
        guard case .saveMacros(let macros) = try Bridge.decodeCommand(from: try object(json)) else { return XCTFail() }
        XCTAssertEqual(macros.count, 1)
        XCTAssertEqual(macros[0].name, "A")
        XCTAssertEqual(macros[0].steps.first?.kind, .wait)
    }

    func testDecodeStartMacro() throws {
        let cmd = try Bridge.decodeCommand(from: try object(#"{"type":"start","mode":"macro","config":{"macroId":"m1","repeat":"times","times":2}}"#))
        guard case .start(let mode, let config) = cmd, mode == .macro, case .macro(let cfg) = config else { return XCTFail() }
        XCTAssertEqual(cfg.macroId, "m1"); XCTAssertEqual(cfg.times, 2)
    }

    func testEncodeMacrosEvent() throws {
        let js = try Bridge.script(for: .macros(list: [Macro(id: "m1", name: "A", steps: [])]))
        XCTAssertTrue(js.contains("\"type\":\"macros\""))
        XCTAssertTrue(js.contains("\"name\":\"A\""))
    }

    func testDecodeStartKeyboard() throws {
        let cmd = try Bridge.decodeCommand(from: try object(#"{"type":"start","mode":"keyboard","config":{"combo":"cmd+KeyS","intervalMs":1000,"repeat":"until","times":50}}"#))
        guard case .start(let mode, let config) = cmd, mode == .keyboard, case .keyboard(let kb) = config else { return XCTFail() }
        XCTAssertEqual(kb.combo, "cmd+KeyS"); XCTAssertEqual(kb.intervalMs, 1000)
    }

    func testEncodeKeyboardConfigEvent() throws {
        let js = try Bridge.script(for: .config(mode: .keyboard, config: .keyboard(KeyboardConfig(combo: "Space", intervalMs: 500, repeat: .times, times: 3))))
        XCTAssertTrue(js.contains("\"mode\":\"keyboard\""))
        XCTAssertTrue(js.contains("\"combo\":\"Space\""))
    }

    func testDecodeApplyProfile() throws {
        guard case .applyProfile(let id) = try Bridge.decodeCommand(from: try object(#"{"type":"applyProfile","id":"p1"}"#)) else { return XCTFail() }
        XCTAssertEqual(id, "p1")
    }

    func testDecodeSaveProfiles() throws {
        let json = #"{"type":"saveProfiles","profiles":[{"id":"p1","name":"A","clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":1,"y":2},"jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true},"wakeLock":{"keepDisplayAwake":true,"keepSystemAwake":false},"antiAFK":{"intervalSec":60,"distancePx":30,"keepAwake":true},"keyboard":{"combo":"Space","intervalMs":1000,"repeat":"until","times":50},"device":"mouse"}]}"#
        guard case .saveProfiles(let profiles) = try Bridge.decodeCommand(from: try object(json)) else { return XCTFail() }
        XCTAssertEqual(profiles.count, 1); XCTAssertEqual(profiles[0].name, "A"); XCTAssertEqual(profiles[0].device, "mouse")
    }

    func testEncodeProfilesEvent() throws {
        let p = Profile(id: "p1", name: "A", clicker: ClickerConfig(intervalMs: 100, button: .left, clickType: .single, repeat: .until, times: 50, position: .current, x: 1, y: 2), jiggler: JigglerConfig(intervalSec: 30, distancePx: 40, mode: .zen, keepAwake: true, idleOnly: true), wakeLock: WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: false), antiAFK: AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true), keyboard: KeyboardConfig(combo: "Space", intervalMs: 1000, repeat: .until, times: 50), device: "mouse")
        let js = try Bridge.script(for: .profiles(list: [p]))
        XCTAssertTrue(js.contains("\"type\":\"profiles\"")); XCTAssertTrue(js.contains("\"name\":\"A\""))
    }

    func testEncodeLogEvent() throws {
        let js = try Bridge.script(for: .log(message: "Started Auto Clicker", level: "info"))
        XCTAssertTrue(js.contains("\"type\":\"log\"")); XCTAssertTrue(js.contains("\"message\":\"Started Auto Clicker\"")); XCTAssertTrue(js.contains("\"level\":\"info\""))
    }

    func testDecodeRejectsNonObjectBody() {
        // JSONSerialization.data(withJSONObject:) raises an uncatchable ObjC
        // exception for these; decodeCommand must throw a Swift error instead.
        XCTAssertThrowsError(try Bridge.decodeCommand(from: "just a string"))
        XCTAssertThrowsError(try Bridge.decodeCommand(from: 42))
        XCTAssertThrowsError(try Bridge.decodeCommand(from: ["a", "b"]))
    }

    func testDecodeRejectsFractionalIntField() throws {
        let json = #"{"type":"start","mode":"clicker","config":{"intervalMs":250.5,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":0,"y":0}}"#
        XCTAssertThrowsError(try Bridge.decodeCommand(from: try object(json)))
    }

    func testEncodePositionPickedCarriesPurpose() throws {
        let js = try Bridge.script(for: .positionPicked(x: 3, y: 4, purpose: "step"))
        XCTAssertTrue(js.contains("\"type\":\"positionPicked\""))
        XCTAssertTrue(js.contains("\"x\":3"))
        XCTAssertTrue(js.contains("\"purpose\":\"step\""))
        let plain = try Bridge.script(for: .positionPicked(x: 3, y: 4, purpose: nil))
        XCTAssertFalse(plain.contains("purpose"))
    }
}
