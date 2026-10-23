import Foundation

protocol AssistantKeychainStoring: Sendable {
    func apiKey(for profileID: UUID) -> String?
    @discardableResult
    func setAPIKey(_ apiKey: String?, for profileID: UUID) -> Bool
    @discardableResult
    func removeAPIKey(for profileID: UUID) -> Bool
}

final class AssistantKeychainStore: AssistantKeychainStoring, @unchecked Sendable {
    private let keychain: CodeEditKeychain

    init(keychain: CodeEditKeychain = CodeEditKeychain(keyPrefix: "ai-assistant.provider.")) {
        self.keychain = keychain
    }

    func apiKey(for profileID: UUID) -> String? {
        keychain.get(profileID.uuidString.lowercased())
    }

    @discardableResult
    func setAPIKey(_ apiKey: String?, for profileID: UUID) -> Bool {
        let value = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            return removeAPIKey(for: profileID)
        }
        return keychain.set(
            value,
            forKey: profileID.uuidString.lowercased(),
            withAccess: .accessibleWhenUnlockedThisDeviceOnly
        )
    }

    @discardableResult
    func removeAPIKey(for profileID: UUID) -> Bool {
        keychain.delete(profileID.uuidString.lowercased())
    }
}

final class InMemoryAssistantKeychainStore: AssistantKeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [UUID: String] = [:]

    init(keys: [UUID: String] = [:]) {
        self.keys = keys
    }

    func apiKey(for profileID: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keys[profileID]
    }

    @discardableResult
    func setAPIKey(_ apiKey: String?, for profileID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let value = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            keys.removeValue(forKey: profileID)
        } else {
            keys[profileID] = value
        }
        return true
    }

    @discardableResult
    func removeAPIKey(for profileID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        keys.removeValue(forKey: profileID)
        return true
    }
}
