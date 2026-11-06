import CryptoKit
import XCTest
@testable import Fiddle

final class SettingsTests: XCTestCase {

    func testDefaultClickerMatchesUIDefaults() {
        let d = Settings.default
        XCTAssertEqual(d.clicker.intervalMs, 100)
        XCTAssertEqual(d.clicker.button, .left)
        XCTAssertEqual(d.clicker.clickType, .single)
        XCTAssertEqual(d.clicker.repeat, .until)
        XCTAssertEqual(d.clicker.times, 50)
        XCTAssertEqual(d.clicker.position, .current)
    }

    func testDefaultJigglerMatchesUIDefaults() {
        let d = Settings.default
        XCTAssertEqual(d.jiggler.intervalSec, 30)
        XCTAssertEqual(d.jiggler.distancePx, 40)
        XCTAssertEqual(d.jiggler.mode, .zen)
        XCTAssertTrue(d.jiggler.keepAwake)
        XCTAssertTrue(d.jiggler.idleOnly)
    }

    func testCodableRoundTrip() throws {
        let original = Settings.default
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(original, restored)
    }

    @MainActor
    func testStorePersistsAcrossInstances() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        var clicker = store.settings.clicker
        clicker.intervalMs = 777
        store.setClicker(clicker)

        let reloaded = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        XCTAssertEqual(reloaded.settings.clicker.intervalMs, 777)
    }

    func testDefaultPrefsAreOff() {
        let p = Settings.default.prefs
        XCTAssertFalse(p.menuBarOnly)
        XCTAssertFalse(p.soundOnClick)
    }

    func testPrefsRoundTrip() throws {
        var s = Settings.default
        s.prefs.soundOnClick = true
        s.prefs.menuBarOnly = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testDecodesLegacySettingsWithoutPrefs() throws {
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.prefs, AppPrefs.default)
    }

    @MainActor
    func testSetPrefUpdatesAndPersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setPref("soundOnClick", .bool(true))
        store.setPref("menuBarOnly", .bool(true))

        let reloaded = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        XCTAssertTrue(reloaded.settings.prefs.soundOnClick)
        XCTAssertTrue(reloaded.settings.prefs.menuBarOnly)
    }

    @MainActor
    func testSetPrefIgnoresUnknownKeyAndWrongType() {
        let scratch = UserDefaults(suiteName: "fiddle.test.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: scratch, keys: SuiteKeyStore(scratch))
        store.setPref("bogus", .bool(true))            // unknown key: no crash, no change
        store.setPref("soundOnClick", .string("yes"))  // wrong type: ignored
        XCTAssertFalse(store.settings.prefs.soundOnClick)
    }

    func testDefaultSkinIsRed() {
        XCTAssertEqual(Settings.default.prefs.skin, "red")
    }

    func testDecodesLegacyPrefsWithoutSkin() throws {
        // prefs present but no skin key (saved before M4)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true},
         "prefs":{"launchAtLogin":false,"menuBarOnly":true,"soundOnClick":false}}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.prefs.skin, "red")
        XCTAssertTrue(s.prefs.menuBarOnly)
    }

    @MainActor
    func testSetPrefPersistsSkin() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setPref("skin", .string("cobalt"))

        let reloaded = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        XCTAssertEqual(reloaded.settings.prefs.skin, "cobalt")
    }

    func testDefaultWakeLockAndAntiAFK() {
        let s = Settings.default
        XCTAssertTrue(s.wakeLock.keepDisplayAwake)
        XCTAssertFalse(s.wakeLock.keepSystemAwake)
        XCTAssertEqual(s.antiAFK.intervalSec, 60)
        XCTAssertEqual(s.antiAFK.distancePx, 30)
        XCTAssertTrue(s.antiAFK.keepAwake)
    }

    func testNewConfigsRoundTripAndLegacyDecode() throws {
        var s = Settings.default
        s.wakeLock.keepSystemAwake = true
        s.antiAFK.intervalSec = 99
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        let migrated = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(migrated.wakeLock, WakeLockConfig(keepDisplayAwake: true, keepSystemAwake: false))
        XCTAssertEqual(migrated.antiAFK, AntiAFKConfig(intervalSec: 60, distancePx: 30, keepAwake: true))
    }

    func testDefaultRecordingIsEmpty() {
        XCTAssertTrue(Settings.default.recording.isEmpty)
    }

    func testRecordingRoundTripAndLegacyDecode() throws {
        var s = Settings.default
        s.recording = [RecordedEvent(kind: .down, button: .left, x: 1, y: 2, delayMs: 0)]
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        let migrated = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertTrue(migrated.recording.isEmpty)
    }

    // One corrupt array element must not reset everything: the bad entry is
    // dropped and the rest of the settings survive.
    func testCorruptArrayElementIsDroppedNotFatal() throws {
        let blob = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true},
         "profiles":[{"id":"p1","name":"Good","device":"mouse"}, 42, {"id":"p2","name":"Also good","device":"mouse"}],
         "macros":[{"id":"m1","name":"A","steps":[]}, "corrupt"],
         "recording":[{"kind":"down","button":"left","x":1,"y":1,"delayMs":0}, {"kind":"down","button":7,"x":1,"y":1,"delayMs":0}]}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(blob.utf8))
        XCTAssertEqual(s.profiles.map(\.id), ["p1", "p2"])
        XCTAssertEqual(s.macros.map(\.id), ["m1"])
        XCTAssertEqual(s.recording.count, 1)
        XCTAssertEqual(s.clicker.intervalMs, 100)
    }

    // A tampered blob must not carry markup into the page through a library id.
    // The hostile entry is dropped like any other corrupt element.
    func testHostileLibraryIdsAreDropped() throws {
        let blob = #"""
        {"profiles":[{"id":"p1","name":"Good","device":"mouse"}, {"id":"\"><img src=x onerror=alert(1)>","name":"Bad","device":"mouse"}],
         "macros":[{"id":"m1\" onmouseover=\"x","name":"Bad","steps":[]}, {"id":"m2","name":"Good","steps":[]}]}
        """#
        let s = try JSONDecoder().decode(Settings.self, from: Data(blob.utf8))
        XCTAssertEqual(s.profiles.map(\.id), ["p1"])
        XCTAssertEqual(s.macros.map(\.id), ["m2"])
    }

    func testRecorderConfigRoundTripAndLegacyDecode() throws {
        var s = Settings.default
        s.recorder = RecorderConfig(repeat: .times, times: 9)
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        let migrated = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(migrated.recorder, RecorderConfig(repeat: .until, times: 5))
    }

    @MainActor
    func testSetRecorderConfigPersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setRecorder(RecorderConfig(repeat: .times, times: 3))
        let reloaded = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        XCTAssertEqual(reloaded.settings.recorder, RecorderConfig(repeat: .times, times: 3))
    }

    @MainActor
    func testSetRecordingPersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setRecording([RecordedEvent(kind: .down, button: .right, x: 7, y: 8, delayMs: 5)])
        let reloaded = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        XCTAssertEqual(reloaded.settings.recording.count, 1)
        XCTAssertEqual(reloaded.settings.recording.first?.button, .right)
    }

    func testDefaultMacrosEmpty() {
        XCTAssertTrue(Settings.default.macros.isEmpty)
    }

    func testMacrosRoundTripAndLegacyDecode() throws {
        var s = Settings.default
        s.macros = [Macro(id: "m1", name: "A", steps: [MacroStep(kind: .wait, button: .left, clickType: .single, x: 0, y: 0, ms: 50)])]
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        XCTAssertTrue(try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8)).macros.isEmpty)
    }

    @MainActor
    func testSetMacrosPersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setMacros([Macro(id: "m1", name: "A", steps: [])])
        XCTAssertEqual(SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults)).settings.macros.count, 1)
    }

    func testDefaultDeviceIsMouse() {
        XCTAssertEqual(Settings.default.prefs.device, "mouse")
    }

    func testDefaultKeyboardConfig() {
        XCTAssertEqual(Settings.default.keyboard.combo, "Space")
        XCTAssertEqual(Settings.default.keyboard.repeat, .until)
    }

    func testKeyboardAndDeviceRoundTripAndLegacyDecode() throws {
        var s = Settings.default
        s.keyboard.combo = "cmd+KeyS"; s.prefs.device = "keyboard"
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        let migrated = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(migrated.prefs.device, "mouse")
        XCTAssertEqual(migrated.keyboard.combo, "Space")
    }

    @MainActor
    func testSetPrefDevicePersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setPref("device", .string("keyboard"))
        XCTAssertEqual(SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults)).settings.prefs.device, "keyboard")
    }

    private func sampleProfile(_ id: String) -> Profile {
        Profile(id: id, name: "P-\(id)",
                clicker: Settings.default.clicker, jiggler: Settings.default.jiggler,
                wakeLock: Settings.default.wakeLock, antiAFK: Settings.default.antiAFK,
                keyboard: Settings.default.keyboard, device: "keyboard")
    }

    func testDefaultProfilesEmpty() {
        XCTAssertTrue(Settings.default.profiles.isEmpty)
    }

    func testProfilesRoundTripAndLegacyDecode() throws {
        var s = Settings.default
        s.profiles = [sampleProfile("1")]
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true}}
        """
        XCTAssertTrue(try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8)).profiles.isEmpty)
    }

    @MainActor
    func testSetProfilesPersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setProfiles([sampleProfile("1"), sampleProfile("2")])
        XCTAssertEqual(SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults)).settings.profiles.count, 2)
    }

    func testDefaultInterfaceModeIsAdvanced() {
        XCTAssertEqual(Settings.default.prefs.interfaceMode, "advanced")
    }

    func testLegacyPrefsDefaultInterfaceMode() throws {
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true},
         "prefs":{"launchAtLogin":false,"menuBarOnly":false,"soundOnClick":false,"skin":"red","device":"mouse"}}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.prefs.interfaceMode, "advanced")
    }

    @MainActor
    func testSetPrefInterfaceModePersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setPref("interfaceMode", .string("simple"))
        XCTAssertEqual(SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults)).settings.prefs.interfaceMode, "simple")
    }

    func testDefaultLastModeIsClicker() {
        XCTAssertEqual(Settings.default.prefs.lastMode, "clicker")
    }

    func testLegacyPrefsDefaultLastMode() throws {
        let legacy = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true},
         "prefs":{"launchAtLogin":false,"menuBarOnly":false,"soundOnClick":false,"skin":"red","device":"mouse","interfaceMode":"advanced"}}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.prefs.lastMode, "clicker")
    }

    @MainActor
    func testSetPrefLastModePersists() {
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setPref("lastMode", .string("jiggler"))
        XCTAssertEqual(SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults)).settings.prefs.lastMode, "jiggler")
    }

    func testLastMacroIdDefaultsEmptyAndPersists() {
        XCTAssertEqual(AppPrefs.default.lastMacroId, "")
        let suite = "fiddle.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults))
        store.setPref("lastMacroId", .string("m42"))
        XCTAssertEqual(SettingsStore(defaults: defaults, keys: SuiteKeyStore(defaults)).settings.prefs.lastMacroId, "m42")
    }

    func testLegacyPrefsDefaultLastMacroId() throws {
        // A prefs blob saved before lastMacroId existed must decode with "".
        let json = #"{"menuBarOnly":false,"soundOnClick":false,"skin":"red","device":"mouse","interfaceMode":"advanced","lastMode":"clicker"}"#
        let prefs = try JSONDecoder().decode(AppPrefs.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.lastMacroId, "")
    }

    // A blob missing the clicker key entirely must not fail the whole decode:
    // the clicker section falls back to Settings.default.clicker and every
    // other section (profiles, macros) survives intact.
    func testDecodeSurvivesMissingClickerSection() throws {
        let blob = """
        {"jiggler":{"intervalSec":30,"distancePx":40,"mode":"zen","keepAwake":true,"idleOnly":true},
         "profiles":[{"id":"p1","name":"Good","device":"mouse"}],
         "macros":[{"id":"m1","name":"A","steps":[]}]}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(blob.utf8))
        XCTAssertEqual(s.clicker, Settings.default.clicker)
        XCTAssertEqual(s.profiles.map(\.id), ["p1"])
        XCTAssertEqual(s.macros.map(\.id), ["m1"])
    }

    // Same as above but for the jiggler key.
    func testDecodeSurvivesMissingJigglerSection() throws {
        let blob = """
        {"clicker":{"intervalMs":100,"button":"left","clickType":"single","repeat":"until","times":50,"position":"current","x":640,"y":480},
         "profiles":[{"id":"p1","name":"Good","device":"mouse"}],
         "macros":[{"id":"m1","name":"A","steps":[]}]}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(blob.utf8))
        XCTAssertEqual(s.jiggler, Settings.default.jiggler)
        XCTAssertEqual(s.profiles.map(\.id), ["p1"])
        XCTAssertEqual(s.macros.map(\.id), ["m1"])
    }
}

/// Keeps the seal key in the test's own defaults suite, so a reloaded store
/// finds the key its predecessor created and nothing touches the real Keychain.
final class SuiteKeyStore: SettingsKeyStore {
    private let defaults: UserDefaults
    var unavailable = false
    init(_ defaults: UserDefaults) { self.defaults = defaults }

    func loadKey() -> SettingsKeyLookup {
        if unavailable { return .unavailable }
        guard let data = defaults.data(forKey: "test.sealKey") else { return .missing }
        return .found(SymmetricKey(data: data))
    }

    func createKey() -> SymmetricKey? {
        if unavailable { return nil }
        let key = SymmetricKey(size: .bits256)
        defaults.set(key.withUnsafeBytes { Data($0) }, forKey: "test.sealKey")
        return key
    }

    func deleteKey() { defaults.removeObject(forKey: "test.sealKey") }
}

@MainActor
final class SettingsSealTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "fiddle.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    /// What a same-user process would plant: a macro, aimed at by lastMode.
    private let planted = #"""
    {"prefs":{"lastMode":"macro","lastMacroId":"m9","menuBarOnly":true},
     "macros":[{"id":"m9","name":"planted","steps":[{"kind":"click","button":"left","clickType":"single","x":10,"y":10,"ms":0}]}]}
    """#

    func testFreshInstallIsArmedAndSurvivesReload() {
        let keys = SuiteKeyStore(defaults)
        let store = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertTrue(store.hotkeyArmed)
        var clicker = store.settings.clicker
        clicker.intervalMs = 321
        store.setClicker(clicker)

        let reloaded = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertEqual(reloaded.settings.clicker.intervalMs, 321)
        XCTAssertTrue(reloaded.hotkeyArmed)
        XCTAssertFalse(reloaded.didRejectTamperedSettings)
    }

    func testRewrittenBlobIsRejected() {
        let keys = SuiteKeyStore(defaults)
        SettingsStore(defaults: defaults, keys: keys).setPref("skin", .string("cobalt"))
        defaults.set(Data(planted.utf8), forKey: "fiddle.settings.v1")

        let reloaded = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertTrue(reloaded.didRejectTamperedSettings)
        XCTAssertEqual(reloaded.settings, .default)
        XCTAssertFalse(reloaded.hotkeyArmed)
        XCTAssertEqual(defaults.data(forKey: "fiddle.settings.v1.rejected"), Data(planted.utf8))
    }

    func testStrippedSealIsRejected() {
        let keys = SuiteKeyStore(defaults)
        SettingsStore(defaults: defaults, keys: keys).setPref("skin", .string("cobalt"))
        defaults.removeObject(forKey: "fiddle.settings.v1.seal")

        let reloaded = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertTrue(reloaded.didRejectTamperedSettings)
        XCTAssertEqual(reloaded.settings, .default)
    }

    func testFlippedArmedBitIsRejected() {
        let keys = SuiteKeyStore(defaults)
        defaults.set(Data(planted.utf8), forKey: "fiddle.settings.v1")
        let adopted = SettingsStore(defaults: defaults, keys: keys)   // legacy adoption, disarmed
        XCTAssertFalse(adopted.hotkeyArmed)
        adopted.setPref("skin", .string("cobalt"))                   // re-sealed, still disarmed
        defaults.set(true, forKey: "fiddle.settings.v1.armed")

        let reloaded = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertTrue(reloaded.didRejectTamperedSettings)
        XCTAssertFalse(reloaded.hotkeyArmed)
    }

    func testLegacyBlobIsAdoptedDisarmedUntilArmed() {
        let keys = SuiteKeyStore(defaults)
        defaults.set(Data(planted.utf8), forKey: "fiddle.settings.v1")

        let store = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertEqual(store.settings.macros.map(\.id), ["m9"])     // nothing the user had is lost
        XCTAssertFalse(store.hotkeyArmed)
        XCTAssertFalse(store.didRejectTamperedSettings)
        XCTAssertFalse(SettingsStore(defaults: defaults, keys: keys).hotkeyArmed)   // stays disarmed across relaunch

        store.armHotkeys()
        let reloaded = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertTrue(reloaded.hotkeyArmed)
        XCTAssertEqual(reloaded.settings.macros.map(\.id), ["m9"])
    }

    // Another process can delete the Keychain item silently, so a missing key
    // must never restore trust in whatever blob is on disk.
    func testDeletedKeyAdoptsDisarmed() {
        let keys = SuiteKeyStore(defaults)
        let store = SettingsStore(defaults: defaults, keys: keys)
        store.armHotkeys()
        keys.deleteKey()
        defaults.set(Data(planted.utf8), forKey: "fiddle.settings.v1")
        defaults.removeObject(forKey: "fiddle.settings.v1.seal")

        let reloaded = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertFalse(reloaded.hotkeyArmed)
    }

    func testUnavailableKeyLoadsDisarmedAndLeavesStoredBlobAlone() {
        let keys = SuiteKeyStore(defaults)
        SettingsStore(defaults: defaults, keys: keys).setPref("skin", .string("cobalt"))
        let sealed = defaults.data(forKey: "fiddle.settings.v1")
        keys.unavailable = true

        let store = SettingsStore(defaults: defaults, keys: keys)
        XCTAssertEqual(store.settings.prefs.skin, "cobalt")
        XCTAssertFalse(store.hotkeyArmed)
        XCTAssertTrue(store.isSealUnavailable)
        store.setPref("skin", .string("emerald"))
        XCTAssertEqual(defaults.data(forKey: "fiddle.settings.v1"), sealed)
    }
}
