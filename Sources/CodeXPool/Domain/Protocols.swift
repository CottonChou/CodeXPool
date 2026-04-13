import Foundation

protocol AccountsStoreRepository: Sendable {
    func loadStore() throws -> AccountsStore
    func saveStore(_ store: AccountsStore) throws
}

protocol SettingsRepository: Sendable {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
}

protocol AuthRepository: Sendable {
    func readCurrentAuth() throws -> JSONValue
    func readCurrentAuthOptional() throws -> JSONValue?
    func readAuth(from url: URL) throws -> JSONValue
    func writeCurrentAuth(_ auth: JSONValue) throws
    func removeCurrentAuth() throws
    func invalidateReadCache()
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth
    func refreshChatGPTAuth(_ auth: JSONValue) async throws -> JSONValue
}

protocol UsageService: Sendable {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot
}

protocol WorkspaceMetadataService: Sendable {
    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata]
}

protocol DateProviding: Sendable {
    func unixSecondsNow() -> Int64
    func unixMillisecondsNow() -> Int64
}

extension DateProviding {
    func unixMillisecondsNow() -> Int64 {
        unixSecondsNow() * 1_000
    }
}

extension AuthRepository {
    func readCurrentExtractedAuth() -> ExtractedAuth? {
        guard let auth = try? readCurrentAuthOptional(),
              let extracted = try? extractAuth(from: auth) else {
            return nil
        }
        return extracted
    }

    func currentAuthAccountKey() -> String? {
        readCurrentExtractedAuth()?.accountKey
    }

    func invalidateReadCache() {}

    func refreshChatGPTAuth(_ auth: JSONValue) async throws -> JSONValue {
        auth
    }
}

protocol CodexCLIServiceProtocol: Sendable {
    func launchApp(workspacePath: String?) throws -> Bool
    func launchApp(workspacePath: String?, environment: [String: String]) throws -> Bool
}

extension CodexCLIServiceProtocol {
    func launchApp(workspacePath: String?, environment: [String: String]) throws -> Bool {
        try launchApp(workspacePath: workspacePath)
    }
}

protocol ChatGPTOAuthLoginServiceProtocol: Sendable {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens
    func signInWithChatGPT(timeoutSeconds: TimeInterval, forcedWorkspaceID: String?) async throws -> ChatGPTOAuthTokens
}

extension ChatGPTOAuthLoginServiceProtocol {
    func signInWithChatGPT(timeoutSeconds: TimeInterval, forcedWorkspaceID: String?) async throws -> ChatGPTOAuthTokens {
        _ = forcedWorkspaceID
        return try await signInWithChatGPT(timeoutSeconds: timeoutSeconds)
    }
}

protocol EditorAppServiceProtocol: Sendable {
    func listInstalledApps() -> [InstalledEditorApp]
    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?)
}

protocol OpencodeAuthSyncServiceProtocol: Sendable {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws
}

protocol LaunchAtStartupServiceProtocol: Sendable {
    func setEnabled(_ enabled: Bool) throws
    func syncWithStoreValue(_ enabled: Bool) throws
}

protocol AccountsCloudSyncServiceProtocol: Sendable {
    func pushLocalAccountsIfNeeded() async throws
    func pullRemoteAccountsIfNeeded(
        currentTime: Int64,
        maximumSnapshotAgeSeconds: Int64
    ) async throws -> AccountsCloudSyncPullResult
    func ensurePushSubscriptionIfNeeded() async throws
}

protocol ConfigTomlServiceProtocol: Sendable {
    func readModelProvider() -> String?
    func writeForAPIKeyMode(profile: APIKeyProfile) throws
    func writeForChatGPTMode() throws
}

protocol ClaudeConfigServiceProtocol: Sendable {
    func writeForAPIKeyMode(profile: ClaudeAPIKeyProfile) throws
    func readCurrentAPIKey() -> String?
    func readCurrentBaseURL() -> String?
}

protocol AuthBackupServiceProtocol: Sendable {
    func backupCurrentAuthFiles() throws
}

protocol CurrentAccountSelectionSyncServiceProtocol: Sendable {
    func recordLocalSelection(accountID: String) async throws
    func pushLocalSelectionIfNeeded() async throws
    func pullRemoteSelectionIfNeeded() async throws -> CurrentAccountSelectionPullResult
    func ensurePushSubscriptionIfNeeded() async throws
}

@MainActor
protocol AccountsManualRefreshServiceProtocol: AnyObject {
    func performManualRefresh() async throws -> [AccountSummary]
    func performManualRefresh(
        onPartialUpdate: @escaping @MainActor ([AccountSummary]) -> Void
    ) async throws -> [AccountSummary]
}

extension AccountsManualRefreshServiceProtocol {
    func performManualRefresh() async throws -> [AccountSummary] {
        try await performManualRefresh(onPartialUpdate: { _ in })
    }
}

@MainActor
protocol AccountsLocalMutationSyncServiceProtocol: AnyObject {
    func acceptLocalAccountsSnapshot(_ accounts: [AccountSummary])
    func syncLocalAccountsMutationNow() async
}
