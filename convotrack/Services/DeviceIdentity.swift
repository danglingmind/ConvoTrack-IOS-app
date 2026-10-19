import Foundation
import Security
import UIKit

/// Opaque per-device id sent as `X-Device-Id`, so the backend can give one free trial per device
/// rather than per account. A random UUID kept in the Keychain — not a hardware or advertising id.
///
/// Keychain items outlive an app delete-and-reinstall, which is the point: a fresh account on the
/// same phone shouldn't mean a fresh trial. `ThisDeviceOnly` keeps it out of iCloud Keychain and
/// encrypted backups, so a new phone restored from backup isn't treated as the old one.
enum DeviceIdentity {
    private static let service = "danglingmind.convotrack.device"
    private static let account = "trial-device-id"

    static let id: String = load() ?? create()

    private static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func create() -> String {
        let value = UUID().uuidString
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        if SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess { return value }
        // Keychain unavailable (rare): the vendor id still ties a trial to this install.
        return UIDevice.current.identifierForVendor?.uuidString ?? value
    }
}
