import Foundation

@MainActor
final class AppContainer {
    let accountsModel: AccountsPageModel
    let settingsModel: SettingsPageModel
    let trayModel: TrayMenuModel

    private let paths: FileSystemPaths
    private let storeRepository: StoreFileRepository
    private let authRepository: AuthFileRepository
    private let settingsCoordinator: SettingsCoordinator

    private lazy var proxyService = SwiftNativeProxyRuntimeService(
        paths: paths,
        storeRepository: storeRepository,
        authRepository: authRepository
    )

    private lazy var cloudflaredService = CloudflaredService(paths: paths)

    private lazy var remoteService = RemoteProxyService(
        repoRoot: RepositoryLocator.findRepoRoot(startingAt: URL(fileURLWithPath: #filePath)),
        sourceAccountStorePath: paths.accountStorePath,
        sourceAuthPath: paths.codexAuthPath
    )

    private lazy var proxyCoordinator = ProxyCoordinator(
        proxyService: proxyService,
        cloudflaredService: cloudflaredService,
        remoteService: remoteService
    )

    private lazy var proxyControlCloudSyncService = CloudKitProxyControlSyncService()

    lazy var proxyControlBridge: ProxyControlBridge = ProxyControlBridge(
        proxyCoordinator: proxyCoordinator,
        settingsCoordinator: settingsCoordinator,
        cloudSyncService: proxyControlCloudSyncService
    )

    lazy var proxyModel: ProxyPageModel = ProxyPageModel(
        coordinator: proxyCoordinator,
        settingsCoordinator: settingsCoordinator,
        proxyControlCloudSyncService: proxyControlCloudSyncService,
        localProxyCommandService: proxyControlBridge
    )

    static func liveOrCrash() -> AppContainer {
        do {
            let paths = try FileSystemPaths.live()
            let storeRepository = StoreFileRepository(paths: paths)
            let authRepository = AuthFileRepository(paths: paths)
            let initialAccounts = initialAccountsSnapshot(using: storeRepository)
            let usageService = DefaultUsageService(configPath: paths.codexConfigPath)
            let workspaceMetadataService = DefaultWorkspaceMetadataService(configPath: paths.codexConfigPath)
            let chatGPTOAuthLoginService = OpenAIChatGPTOAuthLoginService(configPath: paths.codexConfigPath)
            let codexCLIService = CodexCLIService()
            let editorAppService = EditorAppService()
            let opencodeSyncService = OpencodeAuthSyncService()
            let launchAtStartupService = LaunchAtStartupService()
            let cloudSyncService = CloudKitAccountsSyncService(storeRepository: storeRepository)
            let cloudSyncAvailabilityService = CloudSyncAvailabilityService()
            let currentAccountSelectionSyncService = CloudKitCurrentAccountSelectionSyncService(
                storeRepository: storeRepository,
                authRepository: authRepository
            )

            let settingsCoordinator = SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: launchAtStartupService
            )
            let accountsCoordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                authRepository: authRepository,
                usageService: usageService,
                workspaceMetadataService: workspaceMetadataService,
                chatGPTOAuthLoginService: chatGPTOAuthLoginService,
                codexCLIService: codexCLIService,
                editorAppService: editorAppService,
                opencodeAuthSyncService: opencodeSyncService
            )
            let trayModel = TrayMenuModel(
                accountsCoordinator: accountsCoordinator,
                settingsCoordinator: settingsCoordinator,
                cloudSyncService: cloudSyncService,
                currentAccountSelectionSyncService: currentAccountSelectionSyncService,
                backgroundRefreshPolicy: .forPlatform(PlatformCapabilities.currentPlatform),
                initialAccounts: initialAccounts
            )
            let settingsModel = SettingsPageModel(
                settingsCoordinator: settingsCoordinator,
                editorAppService: editorAppService,
                onSettingsUpdated: { settings in
                    trayModel.applySettings(settings)
                }
            )

            Task {
                do {
                    try await settingsCoordinator.syncLaunchAtStartupFromStore()
                } catch {
                    // Keep launch non-blocking even if system login item sync fails.
                }
            }

            return AppContainer(
                paths: paths,
                storeRepository: storeRepository,
                authRepository: authRepository,
                settingsCoordinator: settingsCoordinator,
                accountsModel: AccountsPageModel(
                    coordinator: accountsCoordinator,
                    manualRefreshService: trayModel,
                    localAccountsMutationSyncService: trayModel,
                    currentAccountSelectionSyncService: currentAccountSelectionSyncService,
                    cloudSyncAvailabilityService: cloudSyncAvailabilityService,
                    onLocalAccountsChanged: { accounts in
                        trayModel.acceptLocalAccountsSnapshot(accounts)
                    },
                    initialAccounts: initialAccounts
                ),
                settingsModel: settingsModel,
                trayModel: trayModel
            )
        } catch {
            fatalError("Failed to bootstrap Swift migration app: \(error.localizedDescription)")
        }
    }

    private init(
        paths: FileSystemPaths,
        storeRepository: StoreFileRepository,
        authRepository: AuthFileRepository,
        settingsCoordinator: SettingsCoordinator,
        accountsModel: AccountsPageModel,
        settingsModel: SettingsPageModel,
        trayModel: TrayMenuModel
    ) {
        self.paths = paths
        self.storeRepository = storeRepository
        self.authRepository = authRepository
        self.settingsCoordinator = settingsCoordinator
        self.accountsModel = accountsModel
        self.settingsModel = settingsModel
        self.trayModel = trayModel
    }

    private static func initialAccountsSnapshot(
        using storeRepository: StoreFileRepository
    ) -> [AccountSummary] {
        guard let store = try? storeRepository.loadStore() else {
            return []
        }
        return store.accountSummaries(currentAccountID: nil)
    }
}
