import Foundation
import CryptoKit

struct VerifiedLicense {
    let version: Int
    let product: String
    let licenseID: String
    let fullName: String
    let username: String
    let deviceID: String
    let devicePublicKey: String
    let issuedAt: String
    let expiresAt: String
}

enum LicenseVerificationError: LocalizedError {
    case malformedFormat
    case invalidBase64
    case invalidPayload
    case invalidSignature
    case unsupportedVersion
    case unsupportedProduct
    case missingField(String)
    case licenseExpired
    case wrongDevice
    case deviceIdentityUnavailable

    var errorDescription: String? {
        switch self {
        case .malformedFormat:
            return "Invalid license format."
        case .invalidBase64:
            return "Invalid license encoding."
        case .invalidPayload:
            return "Invalid license payload."
        case .invalidSignature:
            return "License signature is invalid."
        case .unsupportedVersion:
            return "This license version is not supported."
        case .unsupportedProduct:
            return "This license is not for SensorSync Recorder."
        case .missingField(let field):
            return "License is missing \(field)."
        case .licenseExpired:
            return "This license has expired."
        case .wrongDevice:
            return "This license is not valid for this iPhone."
        case .deviceIdentityUnavailable:
            return "Unable to access this iPhone's secure device identity."
        }
    }
}

enum LicenseVerifier {
    private static let prefix = "SSLR2"
    private static let product = "iPhoneSensorRecorder"

    private static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MCowBQYDK2VwAyEAibG2q5X6MTwvWfBLBLiKxW7mV7eH44EQNQZ4biNMAdA=
    -----END PUBLIC KEY-----
    """

    static func verify(
        licenseKey: String,
        fullName: String,
        username: String,
        now: Date = Date()
    ) throws -> VerifiedLicense {
        let enteredName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !enteredName.isEmpty else {
            throw LicenseVerificationError.missingField("Full Name")
        }

        guard !enteredUsername.isEmpty else {
            throw LicenseVerificationError.missingField("Username")
        }

        guard !key.isEmpty else {
            throw LicenseVerificationError.missingField("License Key")
        }

        let parts = key.split(separator: ".", omittingEmptySubsequences: false)

        guard parts.count == 3, parts[0] == prefix else {
            throw LicenseVerificationError.malformedFormat
        }

        // IMPORTANT:
        // Verify the exact payload bytes contained in the license.
        // Do not reserialize the JSON before signature verification.
        let payloadBytes = try decodeBase64URL(String(parts[1]))
        let signatureBytes = try decodeBase64URL(String(parts[2]))

        guard signatureBytes.count == 64 else {
            throw LicenseVerificationError.invalidSignature
        }

        let publicKey = try makePublicKey()

        guard publicKey.isValidSignature(
            signatureBytes,
            for: payloadBytes
        ) else {
            throw LicenseVerificationError.invalidSignature
        }

        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadBytes),
            let payload = jsonObject as? [String: Any]
        else {
            throw LicenseVerificationError.invalidPayload
        }

        guard let version = payload["version"] as? Int else {
            throw LicenseVerificationError.missingField("version")
        }

        guard let product = payload["product"] as? String else {
            throw LicenseVerificationError.missingField("product")
        }

        guard
            let licenseID = payload["license_id"] as? String,
            !licenseID.isEmpty
        else {
            throw LicenseVerificationError.missingField("license_id")
        }

        guard
            let payloadName = payload["full_name"] as? String,
            !payloadName.isEmpty
        else {
            throw LicenseVerificationError.missingField("full_name")
        }

        guard
            let payloadUsername = payload["username"] as? String,
            !payloadUsername.isEmpty
        else {
            throw LicenseVerificationError.missingField("username")
        }

        guard
            let deviceID = payload["device_id"] as? String,
            !deviceID.isEmpty
        else {
            throw LicenseVerificationError.missingField("device_id")
        }

        guard
            let devicePublicKey = payload["device_public_key"] as? String,
            !devicePublicKey.isEmpty
        else {
            throw LicenseVerificationError.missingField("device_public_key")
        }

        guard
            let issuedAt = payload["issued_at"] as? String,
            !issuedAt.isEmpty
        else {
            throw LicenseVerificationError.missingField("issued_at")
        }

        guard
            let expiresAt = payload["expires_at"] as? String,
            !expiresAt.isEmpty
        else {
            throw LicenseVerificationError.missingField("expires_at")
        }

        guard version == 2 else {
            throw LicenseVerificationError.unsupportedVersion
        }

        guard product == Self.product else {
            throw LicenseVerificationError.unsupportedProduct
        }

        guard payloadName == enteredName else {
            throw LicenseVerificationError.invalidPayload
        }

        guard payloadUsername == enteredUsername else {
            throw LicenseVerificationError.invalidPayload
        }

        let identity: DeviceIdentity

        do {
        identity = try DeviceIdentity.load()
        } catch {
        throw LicenseVerificationError.deviceIdentityUnavailable
        }

        guard devicePublicKey == identity.publicKeyBase64URL else {
            throw LicenseVerificationError.wrongDevice
        }

        guard deviceID == identity.deviceID else {
            throw LicenseVerificationError.wrongDevice
        }

        guard let expirationDate = parseISO8601(expiresAt) else {
            throw LicenseVerificationError.invalidPayload
        }

        guard expirationDate > now else {
            throw LicenseVerificationError.licenseExpired
        }

        return VerifiedLicense(
            version: version,
            product: product,
            licenseID: licenseID,
            fullName: payloadName,
            username: payloadUsername,
            deviceID: deviceID,
            devicePublicKey: devicePublicKey,
            issuedAt: issuedAt,
            expiresAt: expiresAt
        )
    }

    private static func makePublicKey() throws -> Curve25519.Signing.PublicKey {
        let lines = publicKeyPEM
            .components(separatedBy: .newlines)
            .filter {
                !$0.contains("BEGIN PUBLIC KEY") &&
                !$0.contains("END PUBLIC KEY") &&
                !$0.isEmpty
            }

        guard let der = Data(base64Encoded: lines.joined()) else {
            throw LicenseVerificationError.invalidBase64
        }

        guard der.count == 44 else {
            throw LicenseVerificationError.invalidPayload
        }

        let rawKey = der.suffix(32)

        do {
            return try Curve25519.Signing.PublicKey(
                rawRepresentation: rawKey
            )
        } catch {
            throw LicenseVerificationError.invalidPayload
        }
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        guard !value.contains("=") else {
            throw LicenseVerificationError.invalidBase64
        }

        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        base64 += String(
            repeating: "=",
            count: (4 - base64.count % 4) % 4
        )

        guard let data = Data(base64Encoded: base64) else {
            throw LicenseVerificationError.invalidBase64
        }

        return data
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withColonSeparatorInTimeZone
        ]

        return formatter.date(from: value)
    }
}
