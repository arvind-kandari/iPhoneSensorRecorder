import Foundation
import Combine

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isActivated = false
    @Published private(set) var fullName = ""
    @Published private(set) var username = ""
    @Published private(set) var licenseID = ""

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isActivated = "SensorSync.license.isActivated"
        static let fullName = "SensorSync.license.fullName"
        static let username = "SensorSync.license.username"
        static let licenseID = "SensorSync.license.licenseID"
    }

    init() {
        load()
    }

    func activate(fullName: String, username: String, licenseKey: String) throws {
        let verified = try LicenseVerifier.verify(
            licenseKey: licenseKey,
            fullName: fullName,
            username: username
        )

        self.fullName = verified.fullName
        self.username = verified.username
        self.licenseID = verified.licenseID
        self.isActivated = true

        defaults.set(true, forKey: Keys.isActivated)
        defaults.set(verified.fullName, forKey: Keys.fullName)
        defaults.set(verified.username, forKey: Keys.username)
        defaults.set(verified.licenseID, forKey: Keys.licenseID)
    }

    private func load() {
        guard defaults.bool(forKey: Keys.isActivated) else { return }

        let storedName = defaults.string(forKey: Keys.fullName) ?? ""
        let storedUsername = defaults.string(forKey: Keys.username) ?? ""
        let storedLicenseID = defaults.string(forKey: Keys.licenseID) ?? ""

        guard !storedName.isEmpty, !storedUsername.isEmpty, !storedLicenseID.isEmpty else {
            clearInvalidStoredActivation()
            return
        }

        fullName = storedName
        username = storedUsername
        licenseID = storedLicenseID
        isActivated = true
    }

    private func clearInvalidStoredActivation() {
        defaults.removeObject(forKey: Keys.isActivated)
        defaults.removeObject(forKey: Keys.fullName)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.licenseID)
    }
}
