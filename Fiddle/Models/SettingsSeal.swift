//
//  SettingsSeal.swift
//  Fiddle
//
//  Signs the persisted settings so another process cannot plant automation
//  for fiddle to replay under its Accessibility grant. The UserDefaults domain
//  is writable by any same-user process (fiddle is not sandboxed); the signing
//  key lives in the login Keychain (found by path, never through the search
//  list), where the partition list keeps items that other programs create
//  unreadable to fiddle and fiddle's item unreadable to them. Another program
//  CAN delete the item silently, so a missing key never restores trust:
//  SettingsStore adopts the blob untrusted (see TrustState).
//

import CryptoKit
import Foundation
import Security

enum SettingsKeyLookup {
    case found(SymmetricKey)
    /// No key yet: first launch with sealing, or the item was deleted.
    case missing
    /// An item exists but cannot be read without a prompt (locked keychain,
    /// or an item some other program planted under fiddle's name).
    case unavailable
}

protocol SettingsKeyStore {
    func loadKey() -> SettingsKeyLookup
    /// Create and store a fresh key, or nil if it could not be stored.
    func createKey() -> SymmetricKey?
}

enum SettingsSeal {
    /// HMAC over the hotkey trust state plus the encoded settings, so neither
    /// can be changed independently of the other. The state is length-prefixed
    /// so no split of the same bytes verifies as a different pair.
    static func seal(_ data: Data, state: Data, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message(data, state: state), using: key))
    }

    static func verify(_ data: Data, state: Data, seal: Data, key: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(seal, authenticating: message(data, state: state), using: key)
    }

    private static func message(_ data: Data, state: Data) -> Data {
        var length = UInt32(state.count).bigEndian
        var m = Data(bytes: &length, count: 4)
        m.append(state)
        m.append(data)
        return m
    }
}

/// What fiddle vouches for, sealed beside the settings blob. Kept out of
/// `Settings` so an adopted blob can never carry its own trust.
struct TrustState: Codable, Equatable {
    /// Modes a hotkey may start: every mode for settings fiddle wrote itself,
    /// none for settings adopted without a valid seal until the user starts
    /// each one from fiddle's own UI. Raw `AutomationMode` values.
    var modes: [String]
    /// The bindings fiddle last set, as combo tokens keyed by `HotkeyAction`
    /// raw value. KeyboardShortcuts keeps the live bindings in unsealed
    /// defaults; fiddle puts back any that differ. Nil until first recorded.
    var bindings: [String: String]?
    /// Saved automation that arrived in adopted settings and that the user has
    /// not confirmed yet: macro and profile ids, and the recording. fiddle asks
    /// before playing or applying any of them.
    var unverifiedMacros: [String] = []
    var unverifiedProfiles: [String] = []
    var unverifiedRecording = false

    static let full = TrustState(modes: AutomationMode.allCases.map(\.rawValue), bindings: nil)
    static let none = TrustState(modes: [], bindings: nil)

    init(modes: [String], bindings: [String: String]?) {
        self.modes = modes
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey { case modes, bindings, unverifiedMacros, unverifiedProfiles, unverifiedRecording }

    // 1.1.0 sealed only `modes` and `bindings`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modes = try c.decode([String].self, forKey: .modes)
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings)
        unverifiedMacros = try c.decodeIfPresent([String].self, forKey: .unverifiedMacros) ?? []
        unverifiedProfiles = try c.decodeIfPresent([String].self, forKey: .unverifiedProfiles) ?? []
        unverifiedRecording = try c.decodeIfPresent(Bool.self, forKey: .unverifiedRecording) ?? false
    }
}

/// A key that lives only for this process (the XCTest host).
final class EphemeralSettingsKey: SettingsKeyStore {
    private var key: SymmetricKey?
    func loadKey() -> SettingsKeyLookup { key.map { .found($0) } ?? .missing }
    func createKey() -> SymmetricKey? {
        let fresh = SymmetricKey(size: .bits256)
        key = fresh
        return fresh
    }
}

struct KeychainSettingsKey: SettingsKeyStore {
    private let service: String
    private let account: String

    init(service: String = "com.zapps.fiddle.settings-seal", account: String = "hmac-sha256") {
        self.service = service
        self.account = account
    }

    /// The user's login keychain, found by its fixed path. The keychain search
    /// list, the default keychain, and even which keychain counts as "login"
    /// are per-user settings another process can change, so a lookup that
    /// relied on any of them could be handed a keychain that process controls.
    static func loginKeychain() -> SecKeychain? {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return nil }
        let path = String(cString: dir) + "/Library/Keychains/login.keychain-db"
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid() else { return nil }
        var keychain: SecKeychain?
        guard SecKeychainOpen(path, &keychain) == errSecSuccess else { return nil }
        return keychain
    }

    func loadKey() -> SettingsKeyLookup {
        guard let login = Self.loginKeychain() else { return .unavailable }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchSearchList as String: [login],
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        // A planted item would otherwise raise a Keychain prompt at launch that
        // the user could approve, handing fiddle the attacker's key. Prompts are
        // suppressed for this one read (kSecUseAuthenticationUIFail does not
        // reach the file-based keychain; this deprecated switch does).
        var wasAllowed = DarwinBoolean(true)
        SecKeychainGetUserInteractionAllowed(&wasAllowed)
        SecKeychainSetUserInteractionAllowed(false)
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { return .unavailable }
            return .found(SymmetricKey(data: data))
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    func createKey() -> SymmetricKey? {
        guard let login = Self.loginKeychain() else { return nil }
        let key = SymmetricKey(size: .bits256)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "fiddle settings seal",
            kSecUseKeychain as String: login,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        // A duplicate means some other item already holds the name; never
        // overwrite or trust it.
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}
