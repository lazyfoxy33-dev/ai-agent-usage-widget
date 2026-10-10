import Foundation

enum UsageFetcherError: Error {
    case missingScript
    case timedOut
    case failed(Int32)
    case invalidOutput
}

struct UsageFetcher {
    enum ProviderScope: String {
        case all
        case apiKeyOnly = "api-key"
    }

    static func scriptPath() -> String? {
        if let override = ProcessInfo.processInfo.environment["QUOTAWIDGET_FETCH"] {
            return override
        }
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = resourcePath + "/core/fetch_usage.py"
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }
        let development = FileManager.default.currentDirectoryPath
            + "/../core/fetch_usage.py"
        return FileManager.default.fileExists(atPath: development)
            ? development : nil
    }

    static func environment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        apiKeys: [APIKeyProviderID: String],
        providerScope: ProviderScope = .all
    ) -> [String: String] {
        var env = base
        for (provider, key) in apiKeys {
            env[provider.envName] = key
        }
        if providerScope != .all {
            env["AI_AGENT_USAGE_PROVIDER_SCOPE"] = providerScope.rawValue
        }
        return env
    }

    /// Credentials the Keychain does not have are filled in from `dsh`'s config,
    /// so a provider configured there works without pasting the key again.
    static func mergingExternalCredentials(
        keychain: [APIKeyProviderID: String],
        external: [APIKeyProviderID: String] = DSHCredentials.load()
    ) -> [APIKeyProviderID: String] {
        var merged = external
        for (provider, key) in keychain
        where !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged[provider] = key
        }
        return merged
    }

    static func providerStatus(from json: String, providerKey: String) -> UsageProvider? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerObject = root[providerKey] else {
            return nil
        }
        guard let providerData = try? JSONSerialization.data(withJSONObject: providerObject) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageProvider.self, from: providerData)
    }

    static func preservingLocalAgentProviders(existing existingJSON: String?, in refreshedJSON: String) -> String {
        let localAgentKeys = ["claude", "codex", "kimi"]
        guard
            let existingJSON,
            let existingData = existingJSON.data(using: .utf8),
            let refreshedData = refreshedJSON.data(using: .utf8),
            let existingRoot = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
            var refreshedRoot = try? JSONSerialization.jsonObject(with: refreshedData) as? [String: Any]
        else {
            return refreshedJSON
        }

        for key in localAgentKeys {
            if let existingProvider = existingRoot[key] as? [String: Any] {
                refreshedRoot[key] = existingProvider
            }
        }

        guard
            JSONSerialization.isValidJSONObject(refreshedRoot),
            let data = try? JSONSerialization.data(withJSONObject: refreshedRoot, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else {
            return refreshedJSON
        }
        return json
    }

    static func replacingProvider(
        in json: String,
        providerKey: String,
        provider: UsageProvider
    ) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetcherError.invalidOutput
        }
        let providerData = try JSONEncoder().encode(provider)
        guard let providerObject = try JSONSerialization.jsonObject(with: providerData) as? [String: Any] else {
            throw UsageFetcherError.invalidOutput
        }
        root[providerKey] = providerObject

        let output = try JSONSerialization.data(withJSONObject: root)
        guard let merged = String(data: output, encoding: .utf8),
              (try? UsagePayload.decode(output)) != nil else {
            throw UsageFetcherError.invalidOutput
        }
        return merged
    }

    static func replacingSiliconFlowProvider(
        in json: String,
        consoleProvider: UsageProvider
    ) throws -> String {
        return try replacingProvider(
            in: json,
            providerKey: "siliconflow",
            provider: consoleProvider
        )
    }

    static func fetch(
        timeout: TimeInterval = 30,
        apiKeys: [APIKeyProviderID: String] = [:],
        providerScope: ProviderScope = .all
    ) throws -> String {
        guard let script = scriptPath() else {
            throw UsageFetcherError.missingScript
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script]
        process.environment = environment(apiKeys: apiKeys, providerScope: providerScope)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw UsageFetcherError.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw UsageFetcherError.failed(process.terminationStatus)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let json = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty,
              (try? UsagePayload.decode(Data(json.utf8))) != nil else {
            throw UsageFetcherError.invalidOutput
        }
        return json
    }
}
