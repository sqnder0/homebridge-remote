import Foundation
import Security

/// Minimal keychain wrapper. Readable after first unlock so Siri can run
/// intents while the phone is locked.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "homebridge-remote",
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        var add = query(key)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum Settings {
    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }
    static var username: String {
        get { UserDefaults.standard.string(forKey: "username") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "username") }
    }
    static var password: String {
        get { Keychain.get("password") ?? "" }
        set { Keychain.set(newValue, for: "password") }
    }
    /// True once the user has saved the connection screen at least once.
    static var configured: Bool {
        get { UserDefaults.standard.bool(forKey: "configured") }
        set { UserDefaults.standard.set(newValue, forKey: "configured") }
    }
}

/// A device the user has added to the app (and therefore to Siri).
struct SavedDevice: Codable, Identifiable, Hashable {
    var id: String             // Homebridge uniqueId
    var name: String           // Name Siri listens for (editable)
    var characteristic: String // power characteristic: "On" or "Active"
}

enum DeviceStore {
    private static let key = "savedDevices"

    static func load() -> [SavedDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedDevice].self, from: data) else { return [] }
        return list
    }

    static func save(_ devices: [SavedDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func device(id: String) -> SavedDevice? {
        load().first { $0.id == id }
    }
}
