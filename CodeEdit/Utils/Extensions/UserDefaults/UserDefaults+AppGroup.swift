import Foundation

extension UserDefaults {
    /// The app-group shared defaults used to talk to the "Open with CodeEdit" extension.
    ///
    /// In an unsandboxed build without a provisioning profile the app-group container does
    /// not exist. Constructing `UserDefaults(suiteName:)` for an unprovisioned group makes
    /// `cfprefsd` log noisy "detaching from cfprefsd" warnings, so only build the suite when
    /// the container is actually reachable, and otherwise fall back to standard defaults.
    static var appGroup: UserDefaults {
        let suiteName = "app.codeedit.CodeEdit.shared"
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) != nil else {
            return .standard
        }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
