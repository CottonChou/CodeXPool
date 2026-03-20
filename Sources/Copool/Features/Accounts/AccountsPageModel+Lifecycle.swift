import Foundation

extension AccountsPageModel {
    func loadIfNeeded() async {
        if !hasLoaded {
            await load()
        }
    }

    func load() async {
        async let cloudSyncAvailableTask = cloudSyncAvailabilityService?.isICloudAvailable() ?? true
        do {
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            isCloudSyncAvailable = await cloudSyncAvailableTask
            applyAccounts(accounts)
            hasLoaded = true
        } catch {
            state = .error(message: error.localizedDescription)
            hasLoaded = true
        }
    }

    /// Applies account snapshots produced by the global background refresh pipeline.
    /// This keeps the Accounts page in sync without creating a duplicate timer.
    func syncFromBackgroundRefresh(_ accounts: [AccountSummary]) {
        applyAccounts(accounts)
    }

    func syncRemoteUsageRefreshActivity(isRefreshing: Bool) {
        guard isRemoteUsageRefreshing != isRefreshing else { return }
        isRemoteUsageRefreshing = isRefreshing
    }
}
