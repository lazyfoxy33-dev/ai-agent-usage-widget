import Foundation
import Security

enum APIKeyProviderID: String, CaseIterable, Identifiable {
    case deepseek
    case siliconflow
    case openrouter

    var id: String { rawValue }

    var envName: String {
        switch self {
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .siliconflow: return "SILICONFLOW_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        }
    }
}

protocol CredentialBackend: Sendable {
    func read(service: String, account: String) throws -> String?
    func save(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct APIKeyStore: Sendable {
    static let defaultService = "AI Agent Usage Widget"

    private let backend: CredentialBackend
    let service: String

    init(backend: CredentialBackend = KeychainCredentialBackend(),
         service: String = defaultService) {
        self.backend = backend
        self.service = service
    }

    func read(_ provider: APIKeyProviderID) throws -> String? {
        try backend.read(service: service, account: provider.rawValue)
    }

    func save(_ value: String, for provider: APIKeyProviderID) throws {
        try backend.save(value, service: service, account: provider.rawValue)
    }

    func delete(_ provider: APIKeyProviderID) throws {
        try backend.delete(service: service, account: provider.rawValue)
    }
}

final class InMemoryCredentialBackend: CredentialBackend, @unchecked Sendable {
    private var storage: [String: String] = [:]

    private func key(service: String, account: String) -> String {
        "\(service)|\(account)"
    }

    func read(service: String, account: String) throws -> String? {
        storage[key(service: service, account: account)]
    }

    func save(_ value: String, service: String, account: String) throws {
        storage[key(service: service, account: account)] = value
    }

    func delete(service: String, account: String) throws {
        storage.removeValue(forKey: key(service: service, account: account))
    }
}

enum KeychainError: Error, CustomStringConvertible {
    case operationFailed(status: OSStatus)
    case unexpectedResult

    var description: String {
        switch self {
        case .operationFailed(let status):
            return "Keychain operation failed (status: \(status))"
        case .unexpectedResult:
            return "Keychain returned an unexpected result"
        }
    }
}

struct KeychainCredentialBackend: CredentialBackend {
    func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status: status)
        }
        guard let data = result as? Data else {
            throw KeychainError.unexpectedResult
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedResult
        }

        if try exists(service: service, account: account) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.operationFailed(status: status)
            }
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.operationFailed(status: status)
            }
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status: status)
        }
    }

    private func exists(service: String, account: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status: status)
        }
        return true
    }
}
