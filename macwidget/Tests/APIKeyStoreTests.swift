import Foundation
import XCTest
@testable import QuotaWidgetApp

final class APIKeyStoreTests: XCTestCase {
    func testStoresReadsAndDeletesAPIKeysByProvider() throws {
        let backend = InMemoryCredentialBackend()
        let store = APIKeyStore(backend: backend)

        try store.save("deepseek-key", for: .deepseek)
        try store.save("openrouter-key", for: .openrouter)

        XCTAssertEqual(try store.read(.deepseek), "deepseek-key")
        XCTAssertEqual(try store.read(.openrouter), "openrouter-key")

        try store.delete(.deepseek)
        XCTAssertNil(try store.read(.deepseek))
        XCTAssertEqual(try store.read(.openrouter), "openrouter-key")
    }

    func testAPIKeysAreStoredInSingleCredentialBundle() throws {
        let backend = InMemoryCredentialBackend()
        let store = APIKeyStore(backend: backend)

        try store.save("deepseek-key", for: .deepseek)
        try store.save("openrouter-key", for: .openrouter)

        XCTAssertNil(try backend.read(service: APIKeyStore.defaultService, account: "deepseek"))
        XCTAssertNil(try backend.read(service: APIKeyStore.defaultService, account: "openrouter"))

        let rawBundle = try XCTUnwrap(backend.read(
            service: AppCredentialBundleStore.service,
            account: AppCredentialBundleStore.account
        ))
        let bundle = try JSONDecoder().decode(AppCredentialBundle.self, from: Data(rawBundle.utf8))
        XCTAssertEqual(bundle.apiKeys["deepseek"], "deepseek-key")
        XCTAssertEqual(bundle.apiKeys["openrouter"], "openrouter-key")
    }

    func testMigratesLegacyAPIKeysIntoSingleCredentialBundle() throws {
        let backend = InMemoryCredentialBackend()
        try backend.save("ds-key", service: APIKeyStore.defaultService, account: "deepseek")
        try backend.save("sf-key", service: APIKeyStore.defaultService, account: "siliconflow")
        let store = APIKeyStore(backend: backend)

        XCTAssertEqual(try store.readAll(), [.deepseek: "ds-key"])
        XCTAssertNotNil(try backend.read(
            service: AppCredentialBundleStore.service,
            account: AppCredentialBundleStore.account
        ))
    }

    func testSiliconFlowConsoleSessionIsStoredInCredentialBundle() throws {
        let backend = InMemoryCredentialBackend()
        let store = SiliconFlowConsoleSessionStore(backend: backend)

        try store.saveCookieHeader("sf_session=test")
        try store.saveSubjectID("subject-test-123456")

        XCTAssertNil(try backend.read(
            service: SiliconFlowConsoleSessionStore.defaultService,
            account: SiliconFlowConsoleSessionStore.cookieAccount
        ))
        XCTAssertNil(try backend.read(
            service: SiliconFlowConsoleSessionStore.defaultService,
            account: SiliconFlowConsoleSessionStore.subjectAccount
        ))

        let session = try XCTUnwrap(store.readSession())
        XCTAssertEqual(session.cookieHeader, "sf_session=test")
        XCTAssertEqual(session.subjectID, "subject-test-123456")
    }

    func testUsesKeychainEnvironmentNamesForProviders() {
        XCTAssertEqual(APIKeyProviderID.allCases, [.deepseek, .openrouter])
        XCTAssertEqual(APIKeyProviderID.deepseek.envName, "DEEPSEEK_API_KEY")
        XCTAssertEqual(APIKeyProviderID.openrouter.envName, "OPENROUTER_API_KEY")
    }

    func testSiliconFlowSubjectValidationDoesNotLogIdentifierFragments() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("App/APIKeyStore.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("prefix("))
        XCTAssertFalse(source.contains("suffix("))
        XCTAssertFalse(source.contains("prefix=%@"))
        XCTAssertFalse(source.contains("suffix=%@"))
    }
}
