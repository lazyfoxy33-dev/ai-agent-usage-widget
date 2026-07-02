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

    func testUsesKeychainEnvironmentNamesForProviders() {
        XCTAssertEqual(APIKeyProviderID.deepseek.envName, "DEEPSEEK_API_KEY")
        XCTAssertEqual(APIKeyProviderID.siliconflow.envName, "SILICONFLOW_API_KEY")
        XCTAssertEqual(APIKeyProviderID.openrouter.envName, "OPENROUTER_API_KEY")
    }
}
