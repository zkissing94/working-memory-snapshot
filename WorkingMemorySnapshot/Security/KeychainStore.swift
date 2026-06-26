import Foundation
import Security

protocol LMStudioTokenStore: Sendable {
    func loadToken() async throws -> String?
    func saveToken(_ token: String?) async throws
    func deleteToken() async throws
}

actor KeychainStore: LMStudioTokenStore {
    static let defaultService = "com.broceps.WorkingMemorySnapshot.lmstudio"
    static let defaultAccount = "apiToken"

    private let service: String
    private let account: String

    init(
        service: String = KeychainStore.defaultService,
        account: String = KeychainStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    func loadToken() async throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainStoreError.invalidStoredData
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func saveToken(_ token: String?) async throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedToken.isEmpty else {
            try await deleteToken()
            return
        }

        let data = Data(trimmedToken.utf8)
        let updateAttributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
    }

    func deleteToken() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainStoreError: Error, Equatable, LocalizedError {
    case invalidStoredData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredData:
            "The saved LM Studio token could not be read."
        case .unexpectedStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
