import Foundation
import Combine

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isActivated = false
    @Published private(set) var fullName = ""
    @Published private(set) var username = ""
    @Published private(set) var licenseID = ""
    @Published private(set) var deviceID = ""
    @Published private(set) var expiresAt = ""

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isActivated = "SensorSync.license.isActivated"
        static let fullName = "SensorSync.license.fullName"
        static let username = "SensorSync.license.username"
        static let licenseID = "SensorSync.license.licenseID"
        static let deviceID = "SensorSync.license.deviceID"
        static let expiresAt = "SensorSync.license.expiresAt"
        static let licenseKey = "SensorSync.license.licenseKey"
    }

    init() {
        load()
    }

    func activate(
        fullName: String,
        username: String,
        licenseKey: String
    ) throws {
        let verified = try LicenseVerifier.verify(
            licenseKey: licenseKey,
            fullName: fullName,
            username: username
        )

        // Keep the complete signed license so the activation can be
        // revalidated later instead of trusting UserDefaults alone.
        let trimmedLicense = licenseKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        self.fullName = verified.fullName
        self.username = verified.username
        self.licenseID = verified.licenseID
        self.deviceID = verified.deviceID
        self.expiresAt = verified.expiresAt
        self.isActivated = true

        defaults.set(true, forKey: Keys.isActivated)
        defaults.set(verified.fullName, forKey: Keys.fullName)
        defaults.set(verified.username, forKey: Keys.username)
        defaults.set(verified.licenseID, forKey: Keys.licenseID)
        defaults.set(verified.deviceID, forKey: Keys.deviceID)
        defaults.set(verified.expiresAt, forKey: Keys.expiresAt)
        defaults.set(trimmedLicense, forKey: Keys.licenseKey)
    }

    /// Revalidates the stored signed license against the current device
    /// and current time. This is called whenever the manager is created.
    func refreshValidity() {
        guard
            let storedLicense = defaults.string(forKey: Keys.licenseKey),
            !storedLicense.isEmpty
        else {
            clearInvalidStoredActivation()
            return
        }

        do {
            let verified = try LicenseVerifier.verify(
                licenseKey: storedLicense,
                fullName: fullName,
                username: username
            )

            guard verified.licenseID == licenseID else {
                clearInvalidStoredActivation()
                return
            }

            let currentDeviceID: String

            do {
                currentDeviceID = try DeviceIdentity.load().deviceID
            } catch {
                clearInvalidStoredActivation()
                return
            }

            guard verified.deviceID == currentDeviceID else {
                clearInvalidStoredActivation()
                return
            }

            self.fullName = verified.fullName
            self.username = verified.username
            self.licenseID = verified.licenseID
            self.deviceID = verified.deviceID
            self.expiresAt = verified.expiresAt
            self.isActivated = true
        } catch {
            clearInvalidStoredActivation()
        }
    }

    private func load() {
        guard defaults.bool(forKey: Keys.isActivated) else {
            return
        }

        let storedName = defaults.string(forKey: Keys.fullName) ?? ""
        let storedUsername = defaults.string(forKey: Keys.username) ?? ""
        let storedLicenseID = defaults.string(forKey: Keys.licenseID) ?? ""
        let storedDeviceID = defaults.string(forKey: Keys.deviceID) ?? ""
        let storedExpiresAt = defaults.string(forKey: Keys.expiresAt) ?? ""
        let storedLicense = defaults.string(forKey: Keys.licenseKey) ?? ""

        guard
            !storedName.isEmpty,
            !storedUsername.isEmpty,
            !storedLicenseID.isEmpty,
            !storedDeviceID.isEmpty,
            !storedExpiresAt.isEmpty,
            !storedLicense.isEmpty
        else {
            clearInvalidStoredActivation()
            return
        }

        fullName = storedName
        username = storedUsername
        licenseID = storedLicenseID
        deviceID = storedDeviceID
        expiresAt = storedExpiresAt
        isActivated = true

        // Do not blindly trust the cached activation flag.
        refreshValidity()
    }

    private func clearInvalidStoredActivation() {
        defaults.removeObject(forKey: Keys.isActivated)
        defaults.removeObject(forKey: Keys.fullName)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.licenseID)
        defaults.removeObject(forKey: Keys.deviceID)
        defaults.removeObject(forKey: Keys.expiresAt)
        defaults.removeObject(forKey: Keys.licenseKey)

        isActivated = false
        fullName = ""
        username = ""
        licenseID = ""
        deviceID = ""
        expiresAt = ""
    }
}
