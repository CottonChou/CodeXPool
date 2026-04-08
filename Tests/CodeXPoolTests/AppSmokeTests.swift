import XCTest
@testable import CodeXPool

@MainActor
final class AppSmokeTests: XCTestCase {
    func testAccountsPageLoadSwitchAndSettingsFlow() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = SmokeAccountsStoreRepository(
            store: AccountsStore(
                version: 1,
                accounts: [
                    StoredAccount(
                        id: "acct-current",
                        label: "Current",
                        email: "current@example.com",
                        accountID: "account-current",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("current-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: makeSmokeUsageSnapshot(fetchedAt: now),
                        usageError: nil
                    ),
                    StoredAccount(
                        id: "acct-next",
                        label: "Next",
                        email: "next@example.com",
                        accountID: "account-next",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("next-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: makeSmokeUsageSnapshot(fetchedAt: now),
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-current",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "smoke-device",
                    accountKey: "account-current"
                )
            )
        )
        let settingsRepository = TestSettingsRepository()
        let authRepository = SmokeAuthRepository(currentAccountKey: "account-current")
        let accountsCoordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            settingsRepository: settingsRepository,
            authRepository: authRepository,
            usageService: SmokeUsageService(snapshot: makeSmokeUsageSnapshot(fetchedAt: now)),
            chatGPTOAuthLoginService: SmokeChatLoginService(),
            codexCLIService: SmokeCodexCLIService(),
            editorAppService: SmokeEditorAppService(),
            opencodeAuthSyncService: SmokeOpencodeAuthSyncService(),
            configTomlService: StubConfigTomlService(),
            authBackupService: StubAuthBackupService(),
            dateProvider: SmokeDateProvider(now: now)
        )
        let settingsCoordinator = SettingsCoordinator(
            settingsRepository: settingsRepository,
            launchAtStartupService: SmokeLaunchAtStartupService()
        )
        let accountsModel = AccountsPageModel(
            coordinator: accountsCoordinator,
            currentAccountSelectionSyncService: SmokeCurrentAccountSelectionSyncService(),
            cloudSyncAvailabilityService: CloudSyncAvailabilityService()
        )
        let settingsModel = SettingsPageModel(
            settingsCoordinator: settingsCoordinator,
            editorAppService: SmokeEditorAppService()
        )

        await accountsModel.loadIfNeeded()
        guard case .content(let loadedAccounts) = accountsModel.state else {
            return XCTFail("Expected loaded accounts content state")
        }
        XCTAssertEqual(loadedAccounts.map(\.label), ["Current", "Next"])
        XCTAssertEqual(loadedAccounts.first(where: \.isCurrent)?.id, "acct-current")

        await accountsModel.switchAccount(id: "acct-next")
        guard case .content(let switchedAccounts) = accountsModel.state else {
            return XCTFail("Expected switched accounts content state")
        }
        XCTAssertEqual(switchedAccounts.first(where: \.isCurrent)?.id, "acct-next")
        XCTAssertEqual(authRepository.currentAccountKey, "account-next")

        settingsModel.settings = try await settingsCoordinator.currentSettings()
        settingsModel.setLaunchAtStartup(true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(settingsModel.settings.launchAtStartup)
        XCTAssertEqual(try settingsRepository.loadSettings().launchAtStartup, true)
    }
}

private func makeSmokeUsageSnapshot(fetchedAt: Int64) -> UsageSnapshot {
    UsageSnapshot(
        fetchedAt: fetchedAt,
        planType: "pro",
        fiveHour: nil,
        oneWeek: nil,
        credits: nil
    )
}

private final class SmokeAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var store: AccountsStore

    init(store: AccountsStore) {
        self.store = store
    }

    func loadStore() throws -> AccountsStore {
        lock.lock()
        defer { lock.unlock() }
        return store
    }

    func saveStore(_ store: AccountsStore) throws {
        lock.lock()
        self.store = store
        lock.unlock()
    }
}

private final class SmokeAuthRepository: AuthRepository, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var currentAccountKey: String?
    private var currentAuth: JSONValue

    init(currentAccountKey: String?) {
        self.currentAccountKey = currentAccountKey
        self.currentAuth = .object(["id_token": .string("current-token")])
    }

    func readCurrentAuth() throws -> JSONValue { currentAuth }
    func readCurrentAuthOptional() throws -> JSONValue? { currentAuth }

    func readAuth(from url: URL) throws -> JSONValue {
        _ = url
        return currentAuth
    }

    func writeCurrentAuth(_ auth: JSONValue) throws {
        lock.lock()
        currentAuth = auth
        if case .object(let object) = auth,
           case .string(let token) = object["id_token"] {
            currentAccountKey = token == "next-token" ? "account-next" : "account-current"
        }
        lock.unlock()
    }

    func removeCurrentAuth() throws {
        lock.lock()
        currentAuth = .object([:])
        currentAccountKey = nil
        lock.unlock()
    }

    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue {
        .object([
            "id_token": .string(tokens.idToken),
            "access_token": .string(tokens.accessToken),
            "refresh_token": .string(tokens.refreshToken)
        ])
    }

    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        let token: String
        if case .object(let object) = auth,
           case .string(let idToken) = object["id_token"] {
            token = idToken
        } else {
            token = "current-token"
        }
        let accountID = token == "next-token" ? "account-next" : "account-current"
        return ExtractedAuth(
            accountID: accountID,
            accessToken: "access-token",
            email: accountID == "account-next" ? "next@example.com" : "current@example.com",
            planType: "pro",
            teamName: nil,
            principalID: accountID
        )
    }

}

private struct SmokeUsageService: UsageService {
    let snapshot: UsageSnapshot

    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        _ = accessToken
        _ = accountID
        return snapshot
    }
}

private struct SmokeDateProvider: DateProviding {
    let now: Int64

    func unixSecondsNow() -> Int64 {
        now
    }
}

private struct SmokeChatLoginService: ChatGPTOAuthLoginServiceProtocol {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        _ = timeoutSeconds
        return ChatGPTOAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: "id"
        )
    }
}

private struct SmokeCodexCLIService: CodexCLIServiceProtocol {
    func launchApp(workspacePath: String?) throws -> Bool {
        _ = workspacePath
        return true
    }
}

private struct SmokeEditorAppService: EditorAppServiceProtocol {
    func listInstalledApps() -> [InstalledEditorApp] { [] }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        (targets, nil)
    }
}

private struct SmokeOpencodeAuthSyncService: OpencodeAuthSyncServiceProtocol {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {
        _ = authJSON
    }
}

private final class SmokeLaunchAtStartupService: LaunchAtStartupServiceProtocol, @unchecked Sendable {
    private(set) var enabled = false

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}

private actor SmokeCurrentAccountSelectionSyncService: CurrentAccountSelectionSyncServiceProtocol {
    func recordLocalSelection(accountID: String) async throws {
        _ = accountID
    }

    func pushLocalSelectionIfNeeded() async throws {}

    func pullRemoteSelectionIfNeeded() async throws -> CurrentAccountSelectionPullResult {
        .noChange
    }

    func ensurePushSubscriptionIfNeeded() async throws {}
}

private final class StubConfigTomlService: ConfigTomlServiceProtocol, @unchecked Sendable {
    func readModelProvider() -> String? { nil }
    func writeForAPIKeyMode(profile: APIKeyProfile) throws {}
    func writeForChatGPTMode() throws {}
}

private final class StubAuthBackupService: AuthBackupServiceProtocol, @unchecked Sendable {
    func backupCurrentAuthFiles() throws {}
}
