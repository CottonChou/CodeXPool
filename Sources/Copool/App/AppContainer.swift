import Foundation

@MainActor
struct AppContainer {
    let accountsModel: AccountsPageModel
    let proxyModel: ProxyPageModel
    let settingsModel: SettingsPageModel
    let trayModel: TrayMenuModel

    static func liveOrCrash() -> AppContainer {
        do {
            let paths = try FileSystemPaths.live()
            guard let repoRoot = RepositoryLocator.findRepoRoot(startingAt: URL(fileURLWithPath: #filePath)) else {
                throw AppError.fileNotFound(L10n.tr("error.app.repo_root_not_found"))
            }
            let storeRepository = StoreFileRepository(paths: paths)
            let authRepository = AuthFileRepository(paths: paths)
            let usageService = DefaultUsageService(configPath: paths.codexConfigPath)
            let proxyService = SwiftNativeProxyRuntimeService(
                paths: paths,
                storeRepository: storeRepository,
                authRepository: authRepository
            )
            let cloudflaredService = CloudflaredService(paths: paths)
            let remoteService = RemoteProxyService(
                repoRoot: repoRoot,
                sourceAccountStorePath: paths.accountStorePath
            )
            let codexCLIService = CodexCLIService()
            let editorAppService = EditorAppService()
            let opencodeSyncService = OpencodeAuthSyncService()
            let launchAtStartupService = LaunchAtStartupService()

            let settingsCoordinator = SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: launchAtStartupService
            )
            let accountsCoordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                authRepository: authRepository,
                usageService: usageService,
                codexCLIService: codexCLIService,
                editorAppService: editorAppService,
                opencodeAuthSyncService: opencodeSyncService
            )
            let proxyCoordinator = ProxyCoordinator(
                proxyService: proxyService,
                cloudflaredService: cloudflaredService,
                remoteService: remoteService
            )
            let trayModel = TrayMenuModel(
                accountsCoordinator: accountsCoordinator,
                settingsCoordinator: settingsCoordinator
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
                accountsModel: AccountsPageModel(coordinator: accountsCoordinator),
                proxyModel: ProxyPageModel(
                    coordinator: proxyCoordinator,
                    settingsCoordinator: settingsCoordinator
                ),
                settingsModel: settingsModel,
                trayModel: trayModel
            )
        } catch {
            fatalError("Failed to bootstrap Swift migration app: \(error.localizedDescription)")
        }
    }
}
