import XCTest
@testable import Copool

final class APIKeyProfileTests: XCTestCase {

    // MARK: - Model Tests

    func testAPIKeyProfileMaskedAPIKeyHidesMiddle() {
        let profile = APIKeyProfile(
            id: "test-1",
            label: "Test",
            providerLabel: "OpenAI",
            apiKey: "sk-abc123def456ghi",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            addedAt: 1000,
            updatedAt: 1000
        )

        XCTAssertEqual(profile.maskedAPIKey, "sk-a****6ghi")
    }

    func testAPIKeyProfileMaskedAPIKeyShortKeyAllStars() {
        let profile = APIKeyProfile(
            id: "test-2",
            label: "Short",
            providerLabel: "Test",
            apiKey: "abcd",
            baseURL: "https://example.com",
            model: "test",
            addedAt: 1000,
            updatedAt: 1000
        )

        XCTAssertEqual(profile.maskedAPIKey, "****")
    }

    func testAPIKeyProfileCodableRoundTrip() throws {
        let profile = APIKeyProfile(
            id: "test-1",
            label: "My Profile",
            providerLabel: "OpenAI",
            apiKey: "sk-test123",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            reasoningEffort: "medium",
            wireAPI: "responses",
            addedAt: 1000,
            updatedAt: 2000
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(APIKeyProfile.self, from: data)

        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.label, profile.label)
        XCTAssertEqual(decoded.providerLabel, profile.providerLabel)
        XCTAssertEqual(decoded.apiKey, profile.apiKey)
        XCTAssertEqual(decoded.baseURL, profile.baseURL)
        XCTAssertEqual(decoded.model, profile.model)
        XCTAssertEqual(decoded.reasoningEffort, profile.reasoningEffort)
        XCTAssertEqual(decoded.wireAPI, "responses")
    }

    func testAPIKeyProfileDecodesWithoutWireAPIDefaultsToResponses() throws {
        let json = """
        {
          "id": "p1", "label": "Test", "providerLabel": "X",
          "apiKey": "sk-x", "baseUrl": "https://x.com/v1", "model": "m",
          "addedAt": 1000, "updatedAt": 2000
        }
        """
        let decoded = try JSONDecoder().decode(APIKeyProfile.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.wireAPI, "responses")
    }

    // MARK: - AccountsStore Extension Tests

    func testAccountsStoreDecodesWithEmptyAPIKeyProfiles() throws {
        let json = """
        {
          "version": 1,
          "accounts": [],
          "workspaceDirectory": []
        }
        """

        let store = try JSONDecoder().decode(AccountsStore.self, from: Data(json.utf8))
        XCTAssertEqual(store.apiKeyProfiles, [])
        XCTAssertEqual(store.activeAuthMode, .chatgpt)
        XCTAssertNil(store.currentAPIKeySelection)
    }

    func testAccountsStoreDecodesWithAPIKeyProfiles() throws {
        let json = """
        {
          "version": 1,
          "accounts": [],
          "workspaceDirectory": [],
          "apiKeyProfiles": [
            {
              "id": "p1",
              "label": "Test",
              "providerLabel": "OpenAI",
              "apiKey": "sk-test",
              "baseUrl": "https://api.openai.com/v1",
              "model": "gpt-4o",
              "wireApi": "responses",
              "addedAt": 1000,
              "updatedAt": 2000
            }
          ],
          "activeAuthMode": "apiKey",
          "currentAPIKeySelection": {
            "profileID": "p1",
            "selectedAt": 3000
          }
        }
        """

        let store = try JSONDecoder().decode(AccountsStore.self, from: Data(json.utf8))
        XCTAssertEqual(store.apiKeyProfiles.count, 1)
        XCTAssertEqual(store.apiKeyProfiles[0].label, "Test")
        XCTAssertEqual(store.activeAuthMode, .apiKey)
        XCTAssertEqual(store.currentAPIKeySelection?.profileID, "p1")
    }

    // MARK: - Active Auth Mode Tests

    func testActiveAuthModeEnumCodable() throws {
        let chatgptData = try JSONEncoder().encode(ActiveAuthMode.chatgpt)
        let chatgptDecoded = try JSONDecoder().decode(ActiveAuthMode.self, from: chatgptData)
        XCTAssertEqual(chatgptDecoded, .chatgpt)

        let apiKeyData = try JSONEncoder().encode(ActiveAuthMode.apiKey)
        let apiKeyDecoded = try JSONDecoder().decode(ActiveAuthMode.self, from: apiKeyData)
        XCTAssertEqual(apiKeyDecoded, .apiKey)
    }

    // MARK: - Coordinator CRUD Tests

    func testAddAPIKeyProfile() async throws {
        let store = InMemoryAccountsStoreRepository(store: AccountsStore())
        let coordinator = makeCoordinator(storeRepository: store)

        let profile = APIKeyProfile(
            id: "",
            label: "Test Profile",
            providerLabel: "OpenAI",
            apiKey: "sk-test",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            addedAt: 0,
            updatedAt: 0
        )

        let added = try await coordinator.addAPIKeyProfile(profile)
        XCTAssertFalse(added.id.isEmpty)
        XCTAssertEqual(added.label, "Test Profile")

        let profiles = try await coordinator.listAPIKeyProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].label, "Test Profile")
    }

    func testUpdateAPIKeyProfile() async throws {
        let existing = APIKeyProfile(
            id: "p1",
            label: "Original",
            providerLabel: "OpenAI",
            apiKey: "sk-test",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            addedAt: 1000,
            updatedAt: 1000
        )
        let store = InMemoryAccountsStoreRepository(
            store: AccountsStore(apiKeyProfiles: [existing])
        )
        let coordinator = makeCoordinator(storeRepository: store)

        var updated = existing
        updated.label = "Updated"
        let result = try await coordinator.updateAPIKeyProfile(updated)
        XCTAssertEqual(result.label, "Updated")

        let profiles = try await coordinator.listAPIKeyProfiles()
        XCTAssertEqual(profiles[0].label, "Updated")
    }

    func testDeleteAPIKeyProfile() async throws {
        let existing = APIKeyProfile(
            id: "p1",
            label: "To Delete",
            providerLabel: "OpenAI",
            apiKey: "sk-test",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            addedAt: 1000,
            updatedAt: 1000
        )
        let store = InMemoryAccountsStoreRepository(
            store: AccountsStore(apiKeyProfiles: [existing])
        )
        let coordinator = makeCoordinator(storeRepository: store)

        try await coordinator.deleteAPIKeyProfile(id: "p1")

        let profiles = try await coordinator.listAPIKeyProfiles()
        XCTAssertTrue(profiles.isEmpty)
    }

    func testDeleteAPIKeyProfileClearsCurrentSelectionIfMatching() async throws {
        let existing = APIKeyProfile(
            id: "p1",
            label: "Current",
            providerLabel: "OpenAI",
            apiKey: "sk-test",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            addedAt: 1000,
            updatedAt: 1000
        )
        let store = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                apiKeyProfiles: [existing],
                activeAuthMode: .apiKey,
                currentAPIKeySelection: APIKeySelection(profileID: "p1", selectedAt: 2000)
            )
        )
        let coordinator = makeCoordinator(storeRepository: store)

        try await coordinator.deleteAPIKeyProfile(id: "p1")

        let loadedStore = try store.loadStore()
        XCTAssertNil(loadedStore.currentAPIKeySelection)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        storeRepository: AccountsStoreRepository? = nil
    ) -> AccountsCoordinator {
        AccountsCoordinator(
            storeRepository: storeRepository ?? InMemoryAccountsStoreRepository(store: AccountsStore()),
            settingsRepository: StubSettingsRepository(),
            authRepository: StubAuthRepository(),
            usageService: StubUsageService(),
            chatGPTOAuthLoginService: StubLoginService(),
            codexCLIService: StubCLIService(),
            editorAppService: StubEditorService(),
            opencodeAuthSyncService: StubOpencodeSyncService(),
            configTomlService: StubConfigTomlService(),
            authBackupService: StubBackupService(),
            dateProvider: FixedDateProvider(now: 1_000_000)
        )
    }
}

private final class InMemoryAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store: AccountsStore
    init(store: AccountsStore) { self.store = store }
    func loadStore() throws -> AccountsStore { store }
    func saveStore(_ store: AccountsStore) throws { self.store = store }
}

private final class StubSettingsRepository: SettingsRepository, @unchecked Sendable {
    func loadSettings() throws -> AppSettings { .defaultValue }
    func saveSettings(_ settings: AppSettings) throws {}
}

private final class StubAuthRepository: AuthRepository, @unchecked Sendable {
    func readCurrentAuth() throws -> JSONValue { .object([:]) }
    func readCurrentAuthOptional() throws -> JSONValue? { nil }
    func readAuth(from url: URL) throws -> JSONValue { .object([:]) }
    func writeCurrentAuth(_ auth: JSONValue) throws {}
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue { .object([:]) }
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        ExtractedAuth(accountID: "test", accessToken: "token")
    }
}

private final class StubUsageService: UsageService, @unchecked Sendable {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        UsageSnapshot(fetchedAt: 0, planType: nil, fiveHour: nil, oneWeek: nil, credits: nil)
    }
}

private final class StubLoginService: ChatGPTOAuthLoginServiceProtocol, @unchecked Sendable {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        ChatGPTOAuthTokens(accessToken: "", refreshToken: "", idToken: "")
    }
}

private final class StubCLIService: CodexCLIServiceProtocol, @unchecked Sendable {
    func launchApp(workspacePath: String?) throws -> Bool { false }
}

private final class StubEditorService: EditorAppServiceProtocol, @unchecked Sendable {
    func listInstalledApps() -> [InstalledEditorApp] { [] }
    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) { ([], nil) }
}

private final class StubOpencodeSyncService: OpencodeAuthSyncServiceProtocol, @unchecked Sendable {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {}
}

private final class StubConfigTomlService: ConfigTomlServiceProtocol, @unchecked Sendable {
    func readModelProvider() -> String? { nil }
    func writeForAPIKeyMode(profile: APIKeyProfile) throws {}
    func writeForChatGPTMode() throws {}
}

private final class StubBackupService: AuthBackupServiceProtocol, @unchecked Sendable {
    func backupCurrentAuthFiles() throws {}
}

private struct FixedDateProvider: DateProviding, Sendable {
    let now: Int64
    func unixSecondsNow() -> Int64 { now }
}
