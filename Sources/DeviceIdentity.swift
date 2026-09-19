import Foundation
import CryptoKit
import Security

enum DeviceIdentityError: LocalizedError {
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case invalidStoredPrivateKey

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Unable to store the device identity in Keychain. Error \(status)."
        case .keychainReadFailed(let status):
            return "Unable to read the device identity from Keychain. Error \(status)."
        case .invalidStoredPrivateKey:
            return "The stored device identity is invalid."
        }
    }
}

struct DeviceIdentity {
    let privateKey: Curve25519.Signing.PrivateKey

    static let shared = DeviceIdentity()

    private static let keychainService =
        "com.arvindkandari.iPhoneSensorRecorder.device-identity"
    private static let keychainAccount = "device-signing-private-key"

    private init() {
        do {
            self.privateKey = try Self.loadOrCreatePrivateKey()
        } catch {
            fatalError("Unable to initialize device identity: \(error.localizedDescription)")
        }
    }

    var publicKey: Curve25519.Signing.PublicKey {
        privateKey.publicKey
    }

    /// Full 32-byte public key encoded as unpadded Base64URL.
    var publicKeyBase64URL: String {
        Self.base64URLEncode(publicKey.rawRepresentation)
    }

    /// Human-readable identifier derived from the complete public key.
    /// The full public key remains the cryptographic identity.
    var deviceID: String {
        let digest = SHA256.hash(data: publicKey.rawRepresentation)
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        return "CYM-\(String(hex.prefix(8)))"
    }

    /// Values the company needs to issue a device-bound license.
    var activationRequest: String {
        """
        Device ID: \(deviceID)
        Device Public Key: \(publicKeyBase64URL)
        """
    }

    private static func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let storedData = try loadKeychainData() {
            do {
                return try Curve25519.Signing.PrivateKey(
                    rawRepresentation: storedData
                )
            } catch {
                throw DeviceIdentityError.invalidStoredPrivateKey
            }
        }

        let generated = Curve25519.Signing.PrivateKey()
        try saveKeychainData(generated.rawRepresentation)
        return generated
    }

    private static func loadKeychainData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw DeviceIdentityError.invalidStoredPrivateKey
            }
            return data

        case errSecItemNotFound:
            return nil

        default:
            throw DeviceIdentityError.keychainReadFailed(status)
        }
    }

    private static func saveKeychainData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainWriteFailed(status)
        }
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
