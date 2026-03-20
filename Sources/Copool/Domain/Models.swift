import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case accounts
    case proxy
    case settings

    var id: String { rawValue }
}

struct AccountsStore: Codable, Equatable {
    var version: Int = 1
    var accounts: [StoredAccount] = []
    var currentSelection: CurrentAccountSelection?
    var settings: AppSettings = .defaultValue
}

struct CurrentAccountSelection: Codable, Equatable {
    var accountID: String
    var selectedAt: Int64
    var sourceDeviceID: String
}

struct CurrentAccountSelectionPullResult: Equatable, Sendable {
    var didUpdateSelection: Bool
    var changedCurrentAccount: Bool
    var accountID: String?

    static let noChange = CurrentAccountSelectionPullResult(
        didUpdateSelection: false,
        changedCurrentAccount: false,
        accountID: nil
    )
}

struct AccountsCloudSyncPullResult: Equatable, Sendable {
    var didUpdateAccounts: Bool
    var remoteSyncedAt: Int64?

    static let noChange = AccountsCloudSyncPullResult(
        didUpdateAccounts: false,
        remoteSyncedAt: nil
    )
}

struct StoredAccount: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var email: String?
    var accountID: String
    var planType: String?
    var teamName: String?
    var teamAlias: String?
    var authJSON: JSONValue
    var addedAt: Int64
    var updatedAt: Int64
    var usage: UsageSnapshot?
    var usageError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case email
        case accountID = "accountId"
        case planType
        case teamName
        case teamAlias
        case authJSON = "authJson"
        case addedAt
        case updatedAt
        case usage
        case usageError
    }
}

struct AccountSummary: Equatable, Identifiable {
    var id: String
    var label: String
    var email: String?
    var accountID: String
    var planType: String?
    var teamName: String?
    var teamAlias: String?
    var addedAt: Int64
    var updatedAt: Int64
    var usage: UsageSnapshot?
    var usageError: String?
    var isCurrent: Bool

    var normalizedPlanLabel: String {
        let normalized = (planType ?? usage?.planType ?? "team")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "free":
            return "FREE"
        case "plus":
            return "PLUS"
        case "pro":
            return "PRO"
        case "enterprise":
            return "ENTERPRISE"
        case "business":
            return "BUSINESS"
        default:
            return "TEAM"
        }
    }

    var displayTeamName: String? {
        if let alias = teamAlias?.trimmingCharacters(in: .whitespacesAndNewlines),
           !alias.isEmpty {
            return alias
        }
        if let teamName = teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !teamName.isEmpty {
            return teamName
        }
        return nil
    }

    var shouldDisplayWorkspaceTag: Bool {
        switch normalizedPlanLabel {
        case "TEAM", "BUSINESS", "ENTERPRISE":
            return displayTeamName != nil
        default:
            return false
        }
    }
}

extension AccountsStore {
    func accountSummaries(currentAccountID: String?) -> [AccountSummary] {
        let resolvedCurrentAccountID = resolvedCurrentAccountID(fallbackAuthAccountID: currentAccountID)

        return accounts.map { account in
            AccountSummary(
                id: account.id,
                label: account.label,
                email: account.email,
                accountID: account.accountID,
                planType: account.planType,
                teamName: account.teamName,
                teamAlias: account.teamAlias,
                addedAt: account.addedAt,
                updatedAt: account.updatedAt,
                usage: account.usage,
                usageError: account.usageError,
                isCurrent: resolvedCurrentAccountID == account.accountID
            )
        }
    }

    private func resolvedCurrentAccountID(fallbackAuthAccountID: String?) -> String? {
        if let selection = currentSelection?.accountID,
           accounts.contains(where: { $0.accountID == selection }) {
            return selection
        }
        return fallbackAuthAccountID
    }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Int64
    var planType: String?
    var fiveHour: UsageWindow?
    var oneWeek: UsageWindow?
    var credits: CreditSnapshot?
}

struct UsageWindow: Codable, Equatable {
    var usedPercent: Double
    var windowSeconds: Int64
    var resetAt: Int64?
}

struct CreditSnapshot: Codable, Equatable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}

struct ExtractedAuth: Equatable {
    var accountID: String
    var accessToken: String
    var email: String?
    var planType: String?
    var teamName: String?
}

struct WorkspaceMetadata: Equatable, Sendable {
    var accountID: String
    var workspaceName: String?
    var structure: String?
}

struct ChatGPTOAuthTokens: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var apiKey: String?
}

enum EditorAppID: String, Codable, CaseIterable, Identifiable {
    case vscode
    case vscodeInsiders
    case cursor
    case antigravity
    case kiro
    case trae
    case qoder

    var id: String { rawValue }
}

struct InstalledEditorApp: Equatable, Identifiable {
    var id: EditorAppID
    var label: String
}

struct SwitchAccountExecutionResult: Equatable {
    var usedFallbackCLI: Bool
    var opencodeSynced: Bool
    var opencodeSyncError: String?
    var restartedEditorApps: [EditorAppID]
    var editorRestartError: String?

    static let idle = SwitchAccountExecutionResult(
        usedFallbackCLI: false,
        opencodeSynced: false,
        opencodeSyncError: nil,
        restartedEditorApps: [],
        editorRestartError: nil
    )
}

struct RemoteServerConfig: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var host: String
    var sshPort: Int
    var sshUser: String
    var authMode: String
    var identityFile: String?
    var privateKey: String?
    var password: String?
    var remoteDir: String
    var listenPort: Int
}

struct CloudflaredConfiguration: Codable, Equatable {
    var enabled: Bool
    var tunnelMode: CloudflaredTunnelMode
    var useHTTP2: Bool
    var namedHostname: String

    init(
        enabled: Bool = false,
        tunnelMode: CloudflaredTunnelMode = .quick,
        useHTTP2: Bool = false,
        namedHostname: String = ""
    ) {
        self.enabled = enabled
        self.tunnelMode = tunnelMode
        self.useHTTP2 = useHTTP2
        self.namedHostname = Self.normalizeHostnameDraft(namedHostname)
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case tunnelMode
        case useHTTP2
        case namedHostname
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        tunnelMode = try container.decodeIfPresent(CloudflaredTunnelMode.self, forKey: .tunnelMode) ?? .quick
        useHTTP2 = try container.decodeIfPresent(Bool.self, forKey: .useHTTP2) ?? false
        namedHostname = Self.normalizeHostnameDraft(
            try container.decodeIfPresent(String.self, forKey: .namedHostname) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(tunnelMode, forKey: .tunnelMode)
        try container.encode(useHTTP2, forKey: .useHTTP2)
        try container.encode(namedHostname, forKey: .namedHostname)
    }

    static var defaultValue: CloudflaredConfiguration {
        CloudflaredConfiguration()
    }

    func normalized() -> CloudflaredConfiguration {
        CloudflaredConfiguration(
            enabled: enabled,
            tunnelMode: tunnelMode,
            useHTTP2: useHTTP2,
            namedHostname: namedHostname
        )
    }

    static func normalizeHostnameDraft(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

struct ProxyConfiguration: Codable, Equatable {
    var preferredPortText: String
    var cloudflared: CloudflaredConfiguration

    init(
        preferredPortText: String = String(RemoteServerConfiguration.defaultProxyPort),
        cloudflared: CloudflaredConfiguration = .defaultValue
    ) {
        self.preferredPortText = Self.normalizePreferredPortText(preferredPortText)
        self.cloudflared = cloudflared.normalized()
    }

    static var defaultValue: ProxyConfiguration {
        ProxyConfiguration()
    }

    var preferredPort: Int? {
        Int(preferredPortText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func normalized() -> ProxyConfiguration {
        ProxyConfiguration(
            preferredPortText: preferredPortText,
            cloudflared: cloudflared
        )
    }

    static func normalizePreferredPortText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(RemoteServerConfiguration.defaultProxyPort)
            : trimmed
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtStartup: Bool
    var launchCodexAfterSwitch: Bool
    var autoSmartSwitch: Bool
    var syncOpencodeOpenaiAuth: Bool
    var localProxyHostAPIOnly: Bool
    var restartEditorsOnSwitch: Bool
    var restartEditorTargets: [EditorAppID]
    var autoStartApiProxy: Bool
    var proxyConfiguration: ProxyConfiguration
    var remoteServers: [RemoteServerConfig]
    var locale: String

    enum CodingKeys: String, CodingKey {
        case launchAtStartup
        case launchCodexAfterSwitch
        case autoSmartSwitch
        case syncOpencodeOpenaiAuth
        case localProxyHostAPIOnly
        case restartEditorsOnSwitch
        case restartEditorTargets
        case autoStartApiProxy
        case proxyConfiguration
        case remoteServers
        case locale
    }

    init(
        launchAtStartup: Bool,
        launchCodexAfterSwitch: Bool,
        autoSmartSwitch: Bool,
        syncOpencodeOpenaiAuth: Bool,
        localProxyHostAPIOnly: Bool = false,
        restartEditorsOnSwitch: Bool,
        restartEditorTargets: [EditorAppID],
        autoStartApiProxy: Bool,
        proxyConfiguration: ProxyConfiguration = .defaultValue,
        remoteServers: [RemoteServerConfig],
        locale: String
    ) {
        self.launchAtStartup = launchAtStartup
        self.launchCodexAfterSwitch = launchCodexAfterSwitch
        self.autoSmartSwitch = autoSmartSwitch
        self.syncOpencodeOpenaiAuth = syncOpencodeOpenaiAuth
        self.localProxyHostAPIOnly = localProxyHostAPIOnly
        self.restartEditorsOnSwitch = restartEditorsOnSwitch
        self.restartEditorTargets = restartEditorTargets
        self.autoStartApiProxy = autoStartApiProxy
        self.proxyConfiguration = proxyConfiguration.normalized()
        self.remoteServers = remoteServers
        self.locale = AppLocale.resolve(locale).identifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.defaultValue

        launchAtStartup = try container.decodeIfPresent(Bool.self, forKey: .launchAtStartup) ?? fallback.launchAtStartup
        launchCodexAfterSwitch = try container.decodeIfPresent(Bool.self, forKey: .launchCodexAfterSwitch) ?? fallback.launchCodexAfterSwitch
        autoSmartSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoSmartSwitch) ?? fallback.autoSmartSwitch
        syncOpencodeOpenaiAuth = try container.decodeIfPresent(Bool.self, forKey: .syncOpencodeOpenaiAuth) ?? fallback.syncOpencodeOpenaiAuth
        localProxyHostAPIOnly = try container.decodeIfPresent(Bool.self, forKey: .localProxyHostAPIOnly) ?? fallback.localProxyHostAPIOnly
        restartEditorsOnSwitch = try container.decodeIfPresent(Bool.self, forKey: .restartEditorsOnSwitch) ?? fallback.restartEditorsOnSwitch
        restartEditorTargets = try container.decodeIfPresent([EditorAppID].self, forKey: .restartEditorTargets) ?? fallback.restartEditorTargets
        autoStartApiProxy = try container.decodeIfPresent(Bool.self, forKey: .autoStartApiProxy) ?? fallback.autoStartApiProxy
        proxyConfiguration = try container.decodeIfPresent(ProxyConfiguration.self, forKey: .proxyConfiguration) ?? fallback.proxyConfiguration
        remoteServers = try container.decodeIfPresent([RemoteServerConfig].self, forKey: .remoteServers) ?? fallback.remoteServers

        let rawLocale = try container.decodeIfPresent(String.self, forKey: .locale) ?? fallback.locale
        locale = AppLocale.resolve(rawLocale).identifier
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(launchCodexAfterSwitch, forKey: .launchCodexAfterSwitch)
        try container.encode(autoSmartSwitch, forKey: .autoSmartSwitch)
        try container.encode(syncOpencodeOpenaiAuth, forKey: .syncOpencodeOpenaiAuth)
        try container.encode(localProxyHostAPIOnly, forKey: .localProxyHostAPIOnly)
        try container.encode(restartEditorsOnSwitch, forKey: .restartEditorsOnSwitch)
        try container.encode(restartEditorTargets, forKey: .restartEditorTargets)
        try container.encode(autoStartApiProxy, forKey: .autoStartApiProxy)
        try container.encode(proxyConfiguration, forKey: .proxyConfiguration)
        try container.encode(remoteServers, forKey: .remoteServers)
        try container.encode(locale, forKey: .locale)
    }

    static var defaultValue: AppSettings {
        AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            autoSmartSwitch: false,
            syncOpencodeOpenaiAuth: false,
            localProxyHostAPIOnly: false,
            restartEditorsOnSwitch: false,
            restartEditorTargets: [],
            autoStartApiProxy: false,
            proxyConfiguration: .defaultValue,
            remoteServers: [],
            locale: AppLocale.systemDefault.identifier
        )
    }
}

struct AppSettingsPatch {
    var launchAtStartup: Bool? = nil
    var launchCodexAfterSwitch: Bool? = nil
    var autoSmartSwitch: Bool? = nil
    var syncOpencodeOpenaiAuth: Bool? = nil
    var localProxyHostAPIOnly: Bool? = nil
    var restartEditorsOnSwitch: Bool? = nil
    var restartEditorTargets: [EditorAppID]? = nil
    var autoStartApiProxy: Bool? = nil
    var proxyConfiguration: ProxyConfiguration? = nil
    var remoteServers: [RemoteServerConfig]? = nil
    var locale: String? = nil
}

struct ApiProxyStatus: Codable, Equatable {
    var running: Bool
    var port: Int?
    var apiKey: String?
    var baseURL: String?
    var availableAccounts: Int
    var activeAccountID: String?
    var activeAccountLabel: String?
    var lastError: String?

    static let idle = ApiProxyStatus(
        running: false,
        port: nil,
        apiKey: nil,
        baseURL: nil,
        availableAccounts: 0,
        activeAccountID: nil,
        activeAccountLabel: nil,
        lastError: nil
    )
}

enum CloudflaredTunnelMode: String, Codable, CaseIterable {
    case quick
    case named
}

struct StartCloudflaredTunnelInput: Codable, Equatable {
    var apiProxyPort: Int
    var useHTTP2: Bool
    var mode: CloudflaredTunnelMode
    var named: NamedCloudflaredTunnelInput?
}

struct NamedCloudflaredTunnelInput: Codable, Equatable {
    var apiToken: String
    var accountID: String
    var zoneID: String
    var hostname: String
}

struct CloudflaredStatus: Codable, Equatable {
    var installed: Bool
    var binaryPath: String?
    var running: Bool
    var tunnelMode: CloudflaredTunnelMode?
    var publicURL: String?
    var customHostname: String?
    var useHTTP2: Bool
    var lastError: String?

    static let idle = CloudflaredStatus(
        installed: false,
        binaryPath: nil,
        running: false,
        tunnelMode: nil,
        publicURL: nil,
        customHostname: nil,
        useHTTP2: false,
        lastError: nil
    )
}

struct RemoteProxyStatus: Codable, Equatable, Sendable {
    var installed: Bool
    var serviceInstalled: Bool
    var running: Bool
    var enabled: Bool
    var serviceName: String
    var pid: Int?
    var baseURL: String
    var apiKey: String?
    var lastError: String?
}

struct ProxyControlSnapshot: Codable, Equatable {
    var syncedAt: Int64
    var sourceDeviceID: String
    var proxyStatus: ApiProxyStatus
    var preferredProxyPort: Int?
    var preferredProxyPortText: String? = nil
    var autoStartProxy: Bool
    var cloudflaredStatus: CloudflaredStatus
    var cloudflaredTunnelMode: CloudflaredTunnelMode
    var cloudflaredNamedInput: NamedCloudflaredTunnelInput
    var cloudflaredUseHTTP2: Bool
    var publicAccessEnabled: Bool
    var remoteServers: [RemoteServerConfig]
    var remoteStatusesSyncedAt: Int64?
    var remoteStatuses: [String: RemoteProxyStatus]
    var remoteLogs: [String: String]
    var lastHandledCommandID: String?
    var lastCommandError: String?
}

enum ProxyControlCommandKind: String, Codable {
    case refreshStatus
    case updateProxyConfiguration
    case startProxy
    case stopProxy
    case refreshAPIKey
    case setAutoStartProxy
    case installCloudflared
    case startCloudflared
    case stopCloudflared
    case refreshCloudflared
    case addRemoteServer
    case saveRemoteServer
    case removeRemoteServer
    case refreshRemote
    case deployRemote
    case startRemote
    case stopRemote
    case readRemoteLogs
}

struct ProxyControlCommand: Codable, Equatable, Identifiable {
    var id: String
    var createdAt: Int64
    var sourceDeviceID: String
    var kind: ProxyControlCommandKind
    var preferredProxyPort: Int?
    var autoStartProxy: Bool?
    var cloudflaredInput: StartCloudflaredTunnelInput?
    var proxyConfiguration: ProxyConfiguration? = nil
    var remoteServer: RemoteServerConfig?
    var remoteServerID: String?
    var logLines: Int?
}

struct PendingUpdateInfo: Equatable {
    var currentVersion: String
    var latestVersion: String
    var releaseURL: String
    var notes: String?
    var publishedAt: String?
}
