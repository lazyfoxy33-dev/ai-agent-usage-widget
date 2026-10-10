import Foundation

/// Provider credentials the DeepSeek Harness (`dsh`) already stores.
///
/// `dsh` keeps its own credentials in `~/.dsh/.credentials.yaml` (mode 600).
/// Reading its `refs` mapping lets people who already configured a provider
/// there use it here without pasting the same key twice. Values are read on
/// demand and never copied into our own storage or logs; the Keychain entry
/// always wins when both exist.
enum DSHCredentials {
    static func defaultPath() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".dsh/.credentials.yaml")
    }

    /// Provider -> secret for the providers we can use, when `dsh` has one.
    static func load(path: URL = DSHCredentials.defaultPath()) -> [APIKeyProviderID: String] {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return [:]
        }
        let refs = mapping(in: text, key: "refs")
        var credentials: [APIKeyProviderID: String] = [:]
        for provider in APIKeyProviderID.allCases {
            guard let value = refs[provider.dshRefKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else {
                continue
            }
            credentials[provider] = value
        }
        return credentials
    }

    /// Minimal reader for a flat `key:` mapping block, so we do not need a YAML
    /// dependency inside the app.
    static func mapping(in text: String, key: String) -> [String: String] {
        var result: [String: String] = [:]
        var blockIndent: Int?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let indent = line.prefix { $0 == " " }.count
            if blockIndent == nil {
                if trimmed.hasPrefix("\(key):") {
                    blockIndent = indent
                }
                continue
            }
            if indent <= blockIndent! {
                break
            }
            guard let separator = trimmed.firstIndex(of: ":") else {
                continue
            }
            let name = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !name.isEmpty, !rawValue.isEmpty else {
                continue
            }
            result[name] = rawValue
        }
        return result
    }
}

extension APIKeyProviderID {
    /// Key name `dsh` uses for this provider in its credentials file.
    var dshRefKey: String {
        switch self {
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        }
    }
}
