//
//  SettingsSeal.swift
//  Fiddle
//
//  Signs the persisted settings so another process cannot plant automation
//  for fiddle to replay under its Accessibility grant. The UserDefaults domain
//  is writable by any same-user process (fiddle is not sandboxed); the signing
//  key lives in the login Keychain, where the partition list keeps items that
//  other programs create unreadable to fiddle and fiddle's item unreadable to
//  them. Another program CAN delete the item silently, so a missing key never
//  restores trust: SettingsStore adopts the blob with the hotkey disarmed.
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
    /// HMAC over the encoded settings plus the hotkey-armed bit, so neither
    /// can be changed independently of the other.
    static func seal(_ data: Data, armed: Bool, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message(data, armed: armed), using: key))
    }

    static func verify(_ data: Data, armed: Bool, seal: Data, key: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(seal, authenticating: message(data, armed: armed), using: key)
    }

    private static func message(_ data: Data, armed: Bool) -> Data {
        var m = Data([armed ? 1 : 0])
        m.append(data)
        return m
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
    private let service = "edu.umontana.fiddle.settings-seal"
    private let account = "hmac-sha256"

    func loadKey() -> SettingsKeyLookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
        let key = SymmetricKey(size: .bits256)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "fiddle settings seal",
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        // A duplicate means some other item already holds the name; never
        // overwrite or trust it.
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}
