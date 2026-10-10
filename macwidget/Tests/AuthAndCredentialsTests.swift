import Foundation
import XCTest
@testable import QuotaWidgetApp

final class AuthAndCredentialsTests: XCTestCase {
    // MARK: - OpenRouter OAuth PKCE

    func testCodeChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            OpenRouterAuth.codeChallenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testAuthorizationURLUsesS256Challenge() throws {
        let url = OpenRouterAuth.authorizationURL(challenge: "abc123")
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "openrouter.ai")
        XCTAssertEqual(url.path, "/auth")
        XCTAssertEqual(value("code_challenge"), "abc123")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("callback_url"), OpenRouterAuth.callbackURL.absoluteString)
    }

    func testCodeVerifierIsUrlSafeAndUnique() {
        let first = OpenRouterAuth.makeCodeVerifier()
        let second = OpenRouterAuth.makeCodeVerifier()

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 43)
        XCTAssertNil(first.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizationCodeIsParsedOnlyFromTheCallback() {
        let callback = OpenRouterAuth.callbackURL.absoluteString

        XCTAssertEqual(
            OpenRouterAuth.authorizationCode(from: URL(string: callback + "?code=xyz")!),
            "xyz"
        )
        XCTAssertNil(
            OpenRouterAuth.authorizationCode(from: URL(string: "https://openrouter.ai/auth?code=xyz")!)
        )
        XCTAssertNil(OpenRouterAuth.authorizationCode(from: URL(string: callback)!))
    }

    // MARK: - dsh credentials

    func testReadsProviderKeysFromDSHCredentials() throws {
        let yaml = """
        version: 1
        refs:
          DEEPSEEK_API_KEY: sk-deepseek-value
          OPENROUTER_API_KEY: sk-or-value
          KIMI_CODING_API_KEY: kimi-value
        records:
          deepseek-account-platform/default:
            kind: oauth
        """
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("credentials.yaml")
        try yaml.write(to: path, atomically: true, encoding: .utf8)

        let loaded = DSHCredentials.load(path: path)

        XCTAssertEqual(loaded[.deepseek], "sk-deepseek-value")
        XCTAssertEqual(loaded[.openrouter], "sk-or-value")
        XCTAssertEqual(loaded.count, 2, "only providers this app can use are read")
    }

    func testMissingDSHFileYieldsNoCredentials() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).yaml")
        XCTAssertTrue(DSHCredentials.load(path: path).isEmpty)
    }

    // MARK: - credential merging

    func testKeychainCredentialWinsOverDSH() {
        let merged = UsageFetcher.mergingExternalCredentials(
            keychain: [.deepseek: "keychain-key"],
            external: [.deepseek: "dsh-key", .openrouter: "dsh-openrouter"]
        )

        XCTAssertEqual(merged[.deepseek], "keychain-key")
        XCTAssertEqual(merged[.openrouter], "dsh-openrouter")
    }

    func testBlankKeychainValueDoesNotHideDSHCredential() {
        let merged = UsageFetcher.mergingExternalCredentials(
            keychain: [.deepseek: "   "],
            external: [.deepseek: "dsh-key"]
        )

        XCTAssertEqual(merged[.deepseek], "dsh-key")
    }

    // MARK: - settings model

    func testExternalCredentialCountsAsConfiguredAndIsLabelled() throws {
        let model = AccountSettingsModel(externalCredentials: [.deepseek])

        let deepseek = try XCTUnwrap(model.rows.first { $0.id == .deepseek })
        XCTAssertTrue(deepseek.configured)
        XCTAssertFalse(deepseek.keychainCredential)
        XCTAssertTrue(deepseek.externalCredential)
        XCTAssertEqual(deepseek.detailText, "dsh")

        let openrouter = try XCTUnwrap(model.rows.first { $0.id == .openrouter })
        XCTAssertFalse(openrouter.configured)
    }

    func testConfiguredProviderWithoutDataWaitsForFirstRefresh() throws {
        let model = AccountSettingsModel(externalCredentials: [.deepseek])
        let deepseek = try XCTUnwrap(model.rows.first { $0.id == .deepseek })

        XCTAssertEqual(deepseek.statusText, "等待首次刷新")
    }

    func testNoBalanceSummaryBeforeAnythingWasFetched() throws {
        let model = AccountSettingsModel(externalCredentials: [.deepseek])
        let deepseek = try XCTUnwrap(model.rows.first { $0.id == .deepseek })

        XCTAssertNil(deepseek.balanceSummary, "a dash-and-trend line must not appear without data")
        XCTAssertEqual(deepseek.statusText, "等待首次刷新")
    }

    func testKeychainCredentialTakesPrecedenceInRows() throws {
        let model = AccountSettingsModel(
            configuredAPIKeys: [.deepseek],
            externalCredentials: [.deepseek]
        )

        let deepseek = try XCTUnwrap(model.rows.first { $0.id == .deepseek })
        XCTAssertTrue(deepseek.keychainCredential)
        XCTAssertFalse(deepseek.externalCredential, "a Keychain key is not reported as a dsh key")
        XCTAssertNil(deepseek.detailText)
    }
}
