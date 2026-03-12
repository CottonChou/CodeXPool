import Foundation

protocol AccountsStoreRepository: Sendable {
    func loadStore() throws -> AccountsStore
    func saveStore(_ store: AccountsStore) throws
}

protocol AuthRepository: Sendable {
    func readCurrentAuth() throws -> JSONValue
    func readCurrentAuthOptional() throws -> JSONValue?
    func writeCurrentAuth(_ auth: JSONValue) throws
    func removeCurrentAuth() throws
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth
    func currentAuthAccountID() -> String?
}

protocol UsageService: Sendable {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot
}

protocol DateProviding: Sendable {
    func unixSecondsNow() -> Int64
}

protocol ProxyRuntimeService: Sendable {
    func status() async -> ApiProxyStatus
    func start(preferredPort: Int?) async throws -> ApiProxyStatus
    func stop() async -> ApiProxyStatus
    func refreshAPIKey() async throws -> ApiProxyStatus
    func syncAccountsStore() async throws
}

protocol CloudflaredServiceProtocol: Sendable {
    func status() async -> CloudflaredStatus
    func install() async throws -> CloudflaredStatus
    func start(_ input: StartCloudflaredTunnelInput) async throws -> CloudflaredStatus
    func stop() async -> CloudflaredStatus
}

protocol RemoteProxyServiceProtocol: Sendable {
    func status(server: RemoteServerConfig) async -> RemoteProxyStatus
    func deploy(server: RemoteServerConfig) async throws -> RemoteProxyStatus
    func start(server: RemoteServerConfig) async throws -> RemoteProxyStatus
    func stop(server: RemoteServerConfig) async throws -> RemoteProxyStatus
    func readLogs(server: RemoteServerConfig, lines: Int) async throws -> String
}

protocol UpdateCheckingService: Sendable {
    func checkForUpdates(currentVersion: String) async throws -> PendingUpdateInfo?
}

protocol CodexCLIServiceProtocol: Sendable {
    func launchLogin() throws
    func launchApp(workspacePath: String?) throws -> Bool
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
