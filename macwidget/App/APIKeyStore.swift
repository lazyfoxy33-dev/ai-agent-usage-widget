import Foundation
import Security
import OSLog

enum APIKeyProviderID: String, CaseIterable, Identifiable {
    case deepseek
    case openrouter

    var id: String { rawValue }

    var envName: String {
        switch self {
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        }
    }
}

protocol CredentialBackend: Sendable {
    func read(service: String, account: String) throws -> String?
    func save(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct StoredSiliconFlowConsoleSession: Codable, Equatable, Sendable {
    var cookieHeader: String?
    var subjectID: String?

    static func isValidSubjectID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = trimmed.range(
            of: "^[A-Za-z0-9_-]{8,80}$",
            options: .regularExpression
        ) != nil
        if !valid {
            NSLog("[SFConsole] subjectID rejected: length=%zu prefix=%@ suffix=%@",
                  trimmed.count,
                  String(trimmed.prefix(8)) as NSString,
                  String(trimmed.suffix(4)) as NSString)
        }
        return valid
    }

    var isConfigured: Bool {
        cookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && subjectID.map(Self.isValidSubjectID) == true
    }
}

struct AppCredentialSnapshot: Equatable, Sendable {
    var apiKeys: [APIKeyProviderID: String]
    var siliconFlowConsoleSession: StoredSiliconFlowConsoleSession?
}

struct AppCredentialBundle: Codable, Equatable {
    var apiKeys: [String: String] = [:]
    var siliconFlowConsole: StoredSiliconFlowConsoleSession?

    var isEmpty: Bool {
        apiKeys.isEmpty
            && siliconFlowConsole?.cookieHeader == nil
            && siliconFlowConsole?.subjectID == nil
    }

    func snapshot() -> AppCredentialSnapshot {
        AppCredentialSnapshot(
            apiKeys: Dictionary(uniqueKeysWithValues: APIKeyProviderID.allCases.compactMap { provider in
                guard let value = apiKeys[provider.rawValue] else { return nil }
                return (provider, value)
            }),
            siliconFlowConsoleSession: siliconFlowConsole
        )
    }
}

struct AppCredentialBundleStore: Sendable {
    static let service = APIKeyStore.defaultService
    static let account = "app-credentials-v1"

    private let backend: CredentialBackend

    init(backend: CredentialBackend = KeychainCredentialBackend()) {
        self.backend = backend
    }

    func snapshot() throws -> AppCredentialSnapshot {
        try readOrMigrateBundle().snapshot()
    }

    func readOrMigrateBundle() throws -> AppCredentialBundle {
        if let existing = try readBundle() {
            return existing
        }

        var migrated = AppCredentialBundle()
        for provider in APIKeyProviderID.allCases {
            if let value = try backend.read(service: APIKeyStore.defaultService, account: provider.rawValue),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                migrated.apiKeys[provider.rawValue] = value
            }
        }

        let cookieHeader = try backend.read(
            service: SiliconFlowConsoleSessionStore.defaultService,
            account: SiliconFlowConsoleSessionStore.cookieAccount
        )
        let subjectID = try backend.read(
            service: SiliconFlowConsoleSessionStore.defaultService,
            account: SiliconFlowConsoleSessionStore.subjectAccount
        )
        if cookieHeader != nil || subjectID != nil {
            migrated.siliconFlowConsole = StoredSiliconFlowConsoleSession(
                cookieHeader: cookieHeader,
                subjectID: subjectID
            )
        }

        if !migrated.isEmpty {
            try saveBundle(migrated)
        }
        return migrated
    }

    func update(_ transform: (inout AppCredentialBundle) -> Void) throws {
        var bundle = try readOrMigrateBundle()
        transform(&bundle)
        try saveBundle(bundle)
    }

    private func readBundle() throws -> AppCredentialBundle? {
        guard let raw = try backend.read(service: Self.service, account: Self.account),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(AppCredentialBundle.self, from: data)
    }

    private func saveBundle(_ bundle: AppCredentialBundle) throws {
        let data = try JSONEncoder().encode(bundle)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedResult
        }
        try backend.save(raw, service: Self.service, account: Self.account)
    }
}

struct APIKeyStore: Sendable {
    static let defaultService = "AI Agent Usage Widget"

    private let backend: CredentialBackend
    private let bundleStore: AppCredentialBundleStore
    let service: String

    init(backend: CredentialBackend = KeychainCredentialBackend(),
         service: String = defaultService) {
        self.backend = backend
        self.bundleStore = AppCredentialBundleStore(backend: backend)
        self.service = service
    }

    func read(_ provider: APIKeyProviderID) throws -> String? {
        let bundle = try bundleStore.readOrMigrateBundle()
        return bundle.apiKeys[provider.rawValue]
    }

    func readAll() throws -> [APIKeyProviderID: String] {
        try bundleStore.snapshot().apiKeys
    }

    func save(_ value: String, for provider: APIKeyProviderID) throws {
        try bundleStore.update { bundle in
            bundle.apiKeys[provider.rawValue] = value
        }
    }

    func delete(_ provider: APIKeyProviderID) throws {
        try bundleStore.update { bundle in
            bundle.apiKeys.removeValue(forKey: provider.rawValue)
        }
    }
}

struct SiliconFlowConsoleSessionStore: Sendable {
    static let defaultService = "AI Agent Usage Widget SiliconFlow Console"
    static let cookieAccount = "cookies"
    static let subjectAccount = "subject-id"

    private let backend: CredentialBackend
    private let bundleStore: AppCredentialBundleStore
    let service: String

    init(
        backend: CredentialBackend = KeychainCredentialBackend(),
        service: String = defaultService
    ) {
        self.backend = backend
        self.bundleStore = AppCredentialBundleStore(backend: backend)
        self.service = service
    }

    func readSession() throws -> StoredSiliconFlowConsoleSession? {
        try bundleStore.readOrMigrateBundle().siliconFlowConsole
    }

    func readCookieHeader() throws -> String? {
        try readSession()?.cookieHeader
    }

    func saveCookieHeader(_ value: String) throws {
        try bundleStore.update { bundle in
            var session = bundle.siliconFlowConsole ?? StoredSiliconFlowConsoleSession()
            session.cookieHeader = value
            bundle.siliconFlowConsole = session
        }
    }

    func deleteCookieHeader() throws {
        try bundleStore.update { bundle in
            bundle.siliconFlowConsole?.cookieHeader = nil
        }
    }

    func readSubjectID() throws -> String? {
        try readSession()?.subjectID
    }

    func saveSubjectID(_ value: String) throws {
        try bundleStore.update { bundle in
            var session = bundle.siliconFlowConsole ?? StoredSiliconFlowConsoleSession()
            session.subjectID = value
            bundle.siliconFlowConsole = session
        }
    }

    func deleteSubjectID() throws {
        try bundleStore.update { bundle in
            bundle.siliconFlowConsole?.subjectID = nil
        }
    }
}

enum SiliconFlowConsoleSessionError: Error {
    case loginRequired
    case invalidURL
    case disallowedURL
    case invalidResponse
    case balanceUnavailable
}

struct SiliconFlowConsoleSessionProvider: Sendable {
    typealias FetchData = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let profileURL = URL(string: "https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek")!

    private let sessionStore: SiliconFlowConsoleSessionStore
    private let sessionOverride: StoredSiliconFlowConsoleSession?
    private let fetchData: FetchData

    init(
        sessionStore: SiliconFlowConsoleSessionStore = SiliconFlowConsoleSessionStore(),
        session: StoredSiliconFlowConsoleSession? = nil,
        fetchData: @escaping FetchData = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SiliconFlowConsoleSessionError.invalidResponse
            }
            return (data, httpResponse)
        }
    ) {
        self.sessionStore = sessionStore
        self.sessionOverride = session
        self.fetchData = fetchData
    }

    static func isAllowedProfileURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "cloud.siliconflow.cn"
            && url.path == "/walletd-server/api/v1/subject/profile/peek"
    }

    static func parseProfileData(_ data: Data) throws -> UsageProvider {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["data"] as? [String: Any],
            let financialInfo = payload["financialInfo"] as? [String: Any]
        else {
            throw SiliconFlowConsoleSessionError.invalidResponse
        }

        var amount: Double?
        var sawBalanceField = false
        for key in ["chargeBalance", "availableBalance", "balance", "totalBalance"] {
            guard let rawAmount = financialInfo[key], !(rawAmount is NSNull) else {
                continue
            }
            sawBalanceField = true
            let candidate: Double?
            if let number = rawAmount as? NSNumber {
                candidate = number.doubleValue
            } else if let string = rawAmount as? String {
                candidate = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                candidate = nil
            }
            if let candidate = normalizedConsoleAmount(candidate, for: key),
               candidate >= 0 {
                amount = candidate
                break
            }
        }

        guard let amount else {
            throw sawBalanceField
                ? SiliconFlowConsoleSessionError.balanceUnavailable
                : SiliconFlowConsoleSessionError.invalidResponse
        }

        let currency = (financialInfo["currency"] as? String) ?? "CNY"
        return UsageProvider(
            ok: true,
            kind: "balance",
            source: "console_session",
            live: true,
            fetchedAt: Date().timeIntervalSince1970,
            balance: BalanceInfo(
                amount: amount,
                currency: currency.uppercased(),
                available: true,
                label: "Console Balance"
            )
        )
    }

    private static func normalizedConsoleAmount(_ amount: Double?, for key: String) -> Double? {
        guard let amount else { return nil }
        if key == "balance", amount >= 1_000_000_000 {
            return amount / 1_000_000_000_000
        }
        return amount
    }

    func fetchBalance() async -> UsageProvider {
        guard Self.isAllowedProfileURL(Self.profileURL) else {
            return failure("error")
        }
        let session = sessionOverride ?? (try? sessionStore.readSession())
        guard let cookieHeader = session?.cookieHeader,
              !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failure("login_required")
        }
        guard let subjectID = session?.subjectID,
              StoredSiliconFlowConsoleSession.isValidSubjectID(
                subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return failure("login_required")
        }

        var request = URLRequest(url: Self.profileURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(subjectID, forHTTPHeaderField: "X-Subject-Id")
        request.setValue("true", forHTTPHeaderField: "X-IdiotProofing-With-No-Cache")

        do {
            let (data, response) = try await fetchData(request)
            switch response.statusCode {
            case 200:
                return try Self.parseProfileData(data)
            case 401, 403:
                return failure("login_required")
            case 429:
                return failure("rate_limited")
            case 400:
                if Self.responseContainsInvalidSubject(data) {
                    return failure("invalid_subject")
                }
                return failure("error")
            default:
                return failure("error")
            }
        } catch SiliconFlowConsoleSessionError.balanceUnavailable {
            return failure("balance_unavailable")
        } catch {
            return failure("error")
        }
    }

    private func failure(_ reason: String) -> UsageProvider {
        UsageProvider(
            ok: false,
            reason: reason,
            kind: "balance",
            source: "console_session",
            live: false
        )
    }

    private static func responseContainsInvalidSubject(_ data: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = root["message"] as? String
        else {
            return false
        }
        let normalized = message.lowercased()
        return normalized.contains("subjectid") || normalized.contains("subject id")
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
