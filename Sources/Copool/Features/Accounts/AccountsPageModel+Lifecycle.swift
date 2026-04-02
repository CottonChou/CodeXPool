import Foundation

extension AccountsPageModel {
    private struct PendingWorkspaceDiscoveryInput: Equatable {
        let id: String
        let accountID: String
        let isCurrent: Bool
    }

    func toggleUsageProgressDisplay() async {
        guard let settingsCoordinator else { return }

        let nextMode: UsageProgressDisplayMode = usageProgressDisplayMode == .used ? .remaining : .used

        do {
            let settings = try await settingsCoordinator.updateSettings(
                AppSettingsPatch(usageProgressDisplayMode: nextMode)
            )
            applySettings(settings)
            onSettingsUpdated?(settings)
            notice = NoticeMessage(
                style: .info,
                text: L10n.tr(
                    "accounts.notice.usage_progress_display_changed_format",
                    L10n.tr(settings.usageProgressDisplayMode.localizationKey)
                )
            )
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func applySettings(_ settings: AppSettings) {
        usageProgressDisplayMode = settings.usageProgressDisplayMode
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        async let cloudSyncAvailableTask = cloudSyncAvailabilityService?.isICloudAvailable() ?? true
        do {
            let accounts = try await coordinator.listAccounts()

            if accounts.isEmpty {
                isCloudSyncAvailable = await cloudSyncAvailableTask
            }

            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts)

            if !accounts.isEmpty {
                isCloudSyncAvailable = await cloudSyncAvailableTask
            }

            hasLoaded = true
        } catch {
            state = .error(message: error.localizedDescription)
            hasLoaded = true
        }
    }

    /// Applies account snapshots produced by the global background refresh pipeline.
    /// This keeps the Accounts page in sync without creating a duplicate timer.
    func syncFromBackgroundRefresh(_ accounts: [AccountSummary]) {
        let shouldRefreshPendingWorkspaces = pendingWorkspaceDiscoveryInputs(
            from: currentAccountsForPendingWorkspaceDiscovery
        ) != pendingWorkspaceDiscoveryInputs(from: accounts)
        applyAccounts(accounts)
        guard shouldRefreshPendingWorkspaces else { return }
        schedulePendingWorkspaceRefresh(from: accounts)
    }

    func syncRemoteUsageRefreshActivity(refreshingAccountIDs: Set<String>) {
        if remoteUsageRefreshingAccountIDs != refreshingAccountIDs {
            remoteUsageRefreshingAccountIDs = refreshingAccountIDs
        }

        let isRefreshing = !refreshingAccountIDs.isEmpty
        guard isRemoteUsageRefreshing != isRefreshing else { return }
        isRemoteUsageRefreshing = isRefreshing
    }

    private var currentAccountsForPendingWorkspaceDiscovery: [AccountSummary] {
        guard case .content(let accounts) = state else { return [] }
        return accounts
    }

    private func pendingWorkspaceDiscoveryInputs(
        from accounts: [AccountSummary]
    ) -> [PendingWorkspaceDiscoveryInput] {
        AccountRanking.sortForDisplay(accounts).map {
            PendingWorkspaceDiscoveryInput(
                id: $0.id,
                accountID: $0.accountID,
                isCurrent: $0.isCurrent
            )
        }
    }
}
