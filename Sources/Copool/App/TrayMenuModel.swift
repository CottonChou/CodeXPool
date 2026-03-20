import Foundation
import Combine

extension Notification.Name {
    static let copoolAccountsSnapshotPushDidArrive = Notification.Name("copool.accounts-snapshot.push")
    static let copoolCurrentAccountSelectionPushDidArrive = Notification.Name("copool.current-account-selection.push")
    static let copoolProxyControlPushDidArrive = Notification.Name("copool.proxy-control.push")
    static let copoolLocalProxySnapshotDidUpdate = Notification.Name("copool.proxy.snapshot.local-update")
}

enum ProxyControlNotificationPayloadKey {
    static let snapshot = "snapshot"
}

struct CloudPushPullRetryPolicy: Sendable {
    let retryIntervals: [Duration]

    init(retryIntervals: [Duration]) {
        self.retryIntervals = retryIntervals
    }

    static let nearRealtime = CloudPushPullRetryPolicy(
        retryIntervals: Array(repeating: .milliseconds(250), count: 8)
            + Array(repeating: .seconds(1), count: 20)
    )
}

private enum AccountsUsageRefreshScope {
    case all
    case priority

    func targetAccountIDs(
        from accounts: [AccountSummary],
        now: Int64,
        using policy: AccountsUsageRefreshPlanningPolicy
    ) -> [String] {
        switch self {
        case .all:
            return accounts.map(\.id)
        case .priority:
            return policy.targetAccountIDs(from: accounts, now: now)
        }
    }
}

@MainActor
final class TrayMenuModel: ObservableObject, AccountsManualRefreshServiceProtocol, AccountsLocalMutationSyncServiceProtocol {
    struct BackgroundRefreshPolicy: Sendable {
        let initialRefreshDelay: Duration
        let cloudReconciliationInterval: Duration
        let usageRefreshInterval: Duration
        let refreshUsageOnRecurringTick: Bool
        let cloudSyncMode: AccountsCloudSyncMode
        let applyRemoteSelectionSwitchEffects: Bool

        static func forPlatform(_ platform: RuntimePlatform) -> BackgroundRefreshPolicy {
            switch platform {
            case .macOS:
                return BackgroundRefreshPolicy(
                    initialRefreshDelay: .milliseconds(700),
                    cloudReconciliationInterval: .seconds(3),
                    usageRefreshInterval: .seconds(30),
                    refreshUsageOnRecurringTick: true,
                    cloudSyncMode: .pushLocalAccounts,
                    applyRemoteSelectionSwitchEffects: true
                )
            case .iOS:
                return BackgroundRefreshPolicy(
                    initialRefreshDelay: .milliseconds(700),
                    cloudReconciliationInterval: .seconds(3),
                    usageRefreshInterval: .seconds(30),
                    refreshUsageOnRecurringTick: true,
                    cloudSyncMode: .pullRemoteAccounts,
                    applyRemoteSelectionSwitchEffects: false
                )
            }
        }
    }

    private let accountsCoordinator: AccountsCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let cloudSyncService: AccountsCloudSyncServiceProtocol?
    private let currentAccountSelectionSyncService: CurrentAccountSelectionSyncServiceProtocol?
    private let backgroundRefreshPolicy: BackgroundRefreshPolicy
    private let dateProvider: DateProviding
    private let snapshotFreshnessPolicy: AccountsSnapshotFreshnessPolicy
    private let accountsSyncExecutionPolicy: AccountsSyncExecutionPolicy
    private let usageRefreshPlanningPolicy: AccountsUsageRefreshPlanningPolicy
    private var cloudReconciliationTask: Task<Void, Never>?
    private var usageRefreshTask: Task<Void, Never>?
    private var workspaceMetadataRefreshTask: Task<Void, Never>?
    private var accountsSnapshotPushCancellable: AnyCancellable?
    private var currentSelectionPushCancellable: AnyCancellable?
    private var autoSmartSwitchEnabled = false
    private var accountsRefreshActivityCount = 0
    private var remoteUsageRefreshActivityCount = 0

    @Published var accounts: [AccountSummary] = []
    @Published var notice: String?
    @Published private(set) var isRefreshingAccounts = false
    @Published private(set) var isFetchingRemoteUsage = false

    init(
        accountsCoordinator: AccountsCoordinator,
        settingsCoordinator: SettingsCoordinator,
        cloudSyncService: AccountsCloudSyncServiceProtocol?,
        currentAccountSelectionSyncService: CurrentAccountSelectionSyncServiceProtocol?,
        backgroundRefreshPolicy: BackgroundRefreshPolicy,
        dateProvider: DateProviding = SystemDateProvider(),
        snapshotFreshnessPolicy: AccountsSnapshotFreshnessPolicy = AccountsSnapshotFreshnessPolicy(),
        usageRefreshPlanningPolicy: AccountsUsageRefreshPlanningPolicy = AccountsUsageRefreshPlanningPolicy(),
        initialAccounts: [AccountSummary] = []
    ) {
        self.accountsCoordinator = accountsCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.cloudSyncService = cloudSyncService
        self.currentAccountSelectionSyncService = currentAccountSelectionSyncService
        self.backgroundRefreshPolicy = backgroundRefreshPolicy
        self.dateProvider = dateProvider
        self.snapshotFreshnessPolicy = snapshotFreshnessPolicy
        self.accountsSyncExecutionPolicy = AccountsSyncExecutionPolicy(
            snapshotFreshnessPolicy: snapshotFreshnessPolicy
        )
        self.usageRefreshPlanningPolicy = usageRefreshPlanningPolicy
        self.accounts = initialAccounts
    }

    func startBackgroundRefresh() {
        guard cloudReconciliationTask == nil else { return }
        configureAccountsSnapshotPushHandlingIfNeeded()
        configureCurrentSelectionPushHandlingIfNeeded()
        cloudReconciliationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.backgroundRefreshPolicy.initialRefreshDelay)
            await self.reconcileCloudStateNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: self.backgroundRefreshPolicy.cloudReconciliationInterval)
                await self.reconcileCloudStateNow()
            }
        }
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            guard self.backgroundRefreshPolicy.refreshUsageOnRecurringTick else { return }
            try? await Task.sleep(for: self.backgroundRefreshPolicy.initialRefreshDelay)
            while !Task.isCancelled {
                try? await Task.sleep(for: self.backgroundRefreshPolicy.usageRefreshInterval)
                await self.refreshNow(forceUsageRefresh: true)
            }
        }
    }

    func stopBackgroundRefresh() {
        cloudReconciliationTask?.cancel()
        cloudReconciliationTask = nil
        usageRefreshTask?.cancel()
        usageRefreshTask = nil
        workspaceMetadataRefreshTask?.cancel()
        workspaceMetadataRefreshTask = nil
        accountsSnapshotPushCancellable = nil
        currentSelectionPushCancellable = nil
    }

    deinit {
        cloudReconciliationTask?.cancel()
        usageRefreshTask?.cancel()
        workspaceMetadataRefreshTask?.cancel()
    }

    func refreshNow(forceUsageRefresh: Bool) async {
        guard !isRefreshingAccounts else { return }
        do {
            beginAccountsRefreshActivity()
            defer { endAccountsRefreshActivity() }
            let latestAccounts = try await executeRefresh(
                forceUsageRefresh: forceUsageRefresh,
                failOnCloudSyncError: false
            )
            accounts = latestAccounts
            scheduleWorkspaceMetadataRefresh(forceRemoteCheck: false)
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func reconcileCloudStateNow() async {
        do {
            let latestAccounts = try await executeCloudReconciliation(failOnCloudSyncError: false)
            accounts = latestAccounts
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func refreshCurrentSelectionNow() async {
        do {
            let result = try await reconcileCurrentAccountSelection(failOnError: false)
            guard result.didUpdateSelection else { return }
            accounts = try await accountsCoordinator.listAccounts()
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func performManualRefresh(
        onPartialUpdate: @escaping @MainActor ([AccountSummary]) -> Void
    ) async throws -> [AccountSummary] {
        beginAccountsRefreshActivity()
        defer { endAccountsRefreshActivity() }
        let settings = try await settingsCoordinator.currentSettings()
        applySettings(settings)

        let cloudPullResult = try await pullCloudAccountsIfNeeded(failOnError: false)
        _ = try await reconcileCurrentAccountSelection(failOnError: false)
        let syncDecision = accountsSyncExecutionPolicy.decision(
            cloudSyncMode: backgroundRefreshPolicy.cloudSyncMode,
            forceUsageRefresh: true,
            remoteSyncedAt: cloudPullResult.remoteSyncedAt,
            now: dateProvider.unixSecondsNow()
        )

        let prefersSerialUsageRefresh = backgroundRefreshPolicy.cloudSyncMode == .pullRemoteAccounts
        let targetAccountIDs = AccountsUsageRefreshScope.all.targetAccountIDs(
            from: try await accountsCoordinator.listAccounts(),
            now: dateProvider.unixSecondsNow(),
            using: usageRefreshPlanningPolicy
        )
        var latestAccounts = try await refreshLocalAccounts(
            forceUsageRefresh: syncDecision.shouldRefreshLocalUsage,
            prefersSerialUsageRefresh: prefersSerialUsageRefresh,
            bypassUsageThrottle: syncDecision.shouldRefreshLocalUsage,
            refreshScope: .all,
            targetAccountIDs: targetAccountIDs,
            onPartialUpdate: onPartialUpdate
        )

        if syncDecision.shouldPushLocalSnapshot, !targetAccountIDs.isEmpty {
            try await pushCloudAccountsIfNeeded(failOnError: false)
        }
        _ = try await reconcileCurrentAccountSelection(failOnError: false)
        latestAccounts = try await accountsCoordinator.listAccounts()

        accounts = latestAccounts
        scheduleWorkspaceMetadataRefresh(forceRemoteCheck: true)
        notice = nil
        return latestAccounts
    }

    func acceptLocalAccountsSnapshot(_ accounts: [AccountSummary]) {
        self.accounts = accounts
    }

    func syncLocalAccountsMutationNow() async {
        do {
            try await pushCloudAccountsIfNeeded(failOnError: false)
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func applySettings(_ settings: AppSettings) {
        autoSmartSwitchEnabled = settings.autoSmartSwitch
    }

    var title: String {
        guard let current = accounts.first(where: { $0.isCurrent }) else {
            return L10n.tr("tray.title.placeholder")
        }

        let five = percent(remainingValue(window: current.usage?.fiveHour))
        let week = percent(remainingValue(window: current.usage?.oneWeek))
        return L10n.tr("tray.title.format", five, week)
    }

    func accountLine(_ account: AccountSummary) -> String {
        let prefix = account.isCurrent ? L10n.tr("tray.account.current_prefix") : ""
        let five = percent(remainingValue(window: account.usage?.fiveHour))
        let week = percent(remainingValue(window: account.usage?.oneWeek))
        return L10n.tr("tray.account.line.format", prefix, account.label, five, week)
    }

    private func remainingValue(window: UsageWindow?) -> Double? {
        guard let window else { return nil }
        return max(0, 100 - window.usedPercent)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    private func executeRefresh(
        forceUsageRefresh: Bool,
        failOnCloudSyncError: Bool
    ) async throws -> [AccountSummary] {
        let settings = try await settingsCoordinator.currentSettings()
        applySettings(settings)

        let cloudPullResult = try await pullCloudAccountsIfNeeded(failOnError: failOnCloudSyncError)
        _ = try await reconcileCurrentAccountSelection(failOnError: failOnCloudSyncError)
        let prefersSerialUsageRefresh = backgroundRefreshPolicy.cloudSyncMode == .pullRemoteAccounts
        let syncDecision = accountsSyncExecutionPolicy.decision(
            cloudSyncMode: backgroundRefreshPolicy.cloudSyncMode,
            forceUsageRefresh: forceUsageRefresh,
            remoteSyncedAt: cloudPullResult.remoteSyncedAt,
            now: dateProvider.unixSecondsNow()
        )
        let targetAccountIDs = AccountsUsageRefreshScope.priority.targetAccountIDs(
            from: try await accountsCoordinator.listAccounts(),
            now: dateProvider.unixSecondsNow(),
            using: usageRefreshPlanningPolicy
        )
        var latestAccounts = try await refreshLocalAccounts(
            forceUsageRefresh: syncDecision.shouldRefreshLocalUsage,
            prefersSerialUsageRefresh: prefersSerialUsageRefresh,
            bypassUsageThrottle: false,
            refreshScope: .priority,
            targetAccountIDs: targetAccountIDs,
            onPartialUpdate: nil
        )

        if cloudPullResult.didUpdateAccounts {
            latestAccounts = try await accountsCoordinator.listAccounts()
        }

        if syncDecision.shouldPushLocalSnapshot, !targetAccountIDs.isEmpty {
            try await pushCloudAccountsIfNeeded(failOnError: failOnCloudSyncError)
        }

        if try await reconcileCurrentAccountSelection(
            failOnError: failOnCloudSyncError
        ).didUpdateSelection {
            latestAccounts = try await accountsCoordinator.listAccounts()
        }

        return latestAccounts
    }

    private func executeCloudReconciliation(
        failOnCloudSyncError: Bool
    ) async throws -> [AccountSummary] {
        let cloudPullResult = try await pullCloudAccountsIfNeeded(failOnError: failOnCloudSyncError)
        let selectionPullResult = try await reconcileCurrentAccountSelection(
            failOnError: failOnCloudSyncError
        )
        let latestLocalAccounts = try await accountsCoordinator.listAccounts()

        if backgroundRefreshPolicy.cloudSyncMode == .pushLocalAccounts,
           !latestLocalAccounts.isEmpty,
           !cloudPullResult.didUpdateAccounts {
            try await pushCloudAccountsIfNeeded(failOnError: failOnCloudSyncError)
        }

        if cloudPullResult.didUpdateAccounts || selectionPullResult.didUpdateSelection {
            return try await accountsCoordinator.listAccounts()
        }

        return latestLocalAccounts
    }

    private func refreshLocalAccounts(
        forceUsageRefresh: Bool,
        prefersSerialUsageRefresh: Bool,
        bypassUsageThrottle: Bool,
        refreshScope: AccountsUsageRefreshScope,
        targetAccountIDs: [String],
        onPartialUpdate: (@MainActor ([AccountSummary]) -> Void)?
    ) async throws -> [AccountSummary] {
        let latestAccounts = try await accountsCoordinator.listAccounts()
        if forceUsageRefresh {
            beginRemoteUsageRefreshActivity()
            defer { endRemoteUsageRefreshActivity() }

            let resolvedTargetAccountIDs = targetAccountIDs.isEmpty
                ? refreshScope.targetAccountIDs(
                    from: latestAccounts,
                    now: dateProvider.unixSecondsNow(),
                    using: usageRefreshPlanningPolicy
                )
                : targetAccountIDs
            guard !resolvedTargetAccountIDs.isEmpty else {
                return latestAccounts
            }

            if prefersSerialUsageRefresh {
                _ = try await accountsCoordinator.refreshUsageSerially(
                    forAccountIDs: resolvedTargetAccountIDs,
                    force: bypassUsageThrottle,
                    onPartialUpdate: { accounts in
                        guard let onPartialUpdate else { return }
                        await MainActor.run {
                            onPartialUpdate(accounts)
                        }
                    }
                )
            } else {
                _ = try await accountsCoordinator.refreshUsage(
                    forAccountIDs: resolvedTargetAccountIDs,
                    force: bypassUsageThrottle,
                    onPartialUpdate: { accounts in
                        guard let onPartialUpdate else { return }
                        await MainActor.run {
                            onPartialUpdate(accounts)
                        }
                    }
                )
            }
            if autoSmartSwitchEnabled {
                _ = try await accountsCoordinator.autoSmartSwitchIfNeeded()
            }
        }
        return try await accountsCoordinator.listAccounts()
    }

    private func pullCloudAccountsIfNeeded(
        failOnError: Bool
    ) async throws -> AccountsCloudSyncPullResult {
        guard let cloudSyncService else { return .noChange }

        do {
            let now = dateProvider.unixSecondsNow()
            return try await cloudSyncService.pullRemoteAccountsIfNeeded(
                currentTime: now,
                maximumSnapshotAgeSeconds: snapshotFreshnessPolicy.remoteSnapshotFreshnessWindowSeconds
            )
        } catch {
            if failOnError {
                throw error
            }
            #if DEBUG
            // print("CloudKit background sync skipped:", error.localizedDescription)
            #endif
            return .noChange
        }
    }

    private func pushCloudAccountsIfNeeded(failOnError: Bool) async throws {
        guard let cloudSyncService else { return }

        do {
            try await cloudSyncService.pushLocalAccountsIfNeeded()
        } catch {
            if failOnError {
                throw error
            }
            #if DEBUG
            // print("CloudKit background sync skipped:", error.localizedDescription)
            #endif
        }
    }

    private func scheduleWorkspaceMetadataRefresh(forceRemoteCheck: Bool) {
        workspaceMetadataRefreshTask?.cancel()
        workspaceMetadataRefreshTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.beginAccountsRefreshActivity()
            }
            defer {
                Task { @MainActor [weak self] in
                    self?.endAccountsRefreshActivity()
                }
            }
            do {
                let latestAccounts = try await self.accountsCoordinator.refreshWorkspaceMetadata(
                    forceRemoteCheck: forceRemoteCheck
                )
                guard !Task.isCancelled else { return }
                if self.backgroundRefreshPolicy.cloudSyncMode == .pushLocalAccounts {
                    try await self.pushCloudAccountsIfNeeded(failOnError: false)
                }
                guard !Task.isCancelled else { return }
                self.accounts = latestAccounts
                self.notice = nil
            } catch {
                #if DEBUG
                // print("Workspace metadata refresh skipped:", error.localizedDescription)
                #endif
            }
        }
    }

    private func beginAccountsRefreshActivity() {
        accountsRefreshActivityCount += 1
        if !isRefreshingAccounts {
            isRefreshingAccounts = true
        }
    }

    private func endAccountsRefreshActivity() {
        accountsRefreshActivityCount = max(0, accountsRefreshActivityCount - 1)
        if accountsRefreshActivityCount == 0, isRefreshingAccounts {
            isRefreshingAccounts = false
        }
    }

    private func beginRemoteUsageRefreshActivity() {
        remoteUsageRefreshActivityCount += 1
        if !isFetchingRemoteUsage {
            isFetchingRemoteUsage = true
        }
    }

    private func endRemoteUsageRefreshActivity() {
        remoteUsageRefreshActivityCount = max(0, remoteUsageRefreshActivityCount - 1)
        if remoteUsageRefreshActivityCount == 0, isFetchingRemoteUsage {
            isFetchingRemoteUsage = false
        }
    }

    private func configureAccountsSnapshotPushHandlingIfNeeded() {
        guard accountsSnapshotPushCancellable == nil else { return }

        accountsSnapshotPushCancellable = NotificationCenter.default
            .publisher(for: .copoolAccountsSnapshotPushDidArrive)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleAccountsSnapshotPushNotification()
                }
            }

        Task {
            do {
                try await cloudSyncService?.ensurePushSubscriptionIfNeeded()
            } catch {
                #if DEBUG
                // print("CloudKit accounts snapshot push subscription skipped:", error.localizedDescription)
                #endif
            }
        }
    }

    private func configureCurrentSelectionPushHandlingIfNeeded() {
        guard backgroundRefreshPolicy.applyRemoteSelectionSwitchEffects else { return }
        guard currentSelectionPushCancellable == nil else { return }

        currentSelectionPushCancellable = NotificationCenter.default
            .publisher(for: .copoolCurrentAccountSelectionPushDidArrive)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleCurrentSelectionPushNotification()
                }
            }

        Task {
            do {
                try await currentAccountSelectionSyncService?.ensurePushSubscriptionIfNeeded()
            } catch {
                #if DEBUG
                // print("CloudKit current selection push subscription skipped:", error.localizedDescription)
                #endif
            }
        }
    }

    private func reconcileCurrentAccountSelection(
        failOnError: Bool
    ) async throws -> CurrentAccountSelectionPullResult {
        guard let currentAccountSelectionSyncService else { return .noChange }

        do {
            let pullResult = try await currentAccountSelectionSyncService.pullRemoteSelectionIfNeeded()

            if pullResult.changedCurrentAccount,
               backgroundRefreshPolicy.applyRemoteSelectionSwitchEffects,
               let remoteAccountID = pullResult.accountID {
                try await applyRemoteSelectionSwitchEffects(accountID: remoteAccountID)
                return pullResult
            }

            if !pullResult.didUpdateSelection {
                try await currentAccountSelectionSyncService.pushLocalSelectionIfNeeded()
            }

            return pullResult
        } catch {
            if failOnError {
                throw error
            }
            #if DEBUG
            // print("CloudKit current selection sync skipped:", error.localizedDescription)
            #endif
            return .noChange
        }
    }

    private func handleAccountsSnapshotPushNotification() async {
        do {
            let pullResult = try await pullCloudAccountsForPushNotification()
            guard pullResult.didUpdateAccounts else { return }
            accounts = try await accountsCoordinator.listAccounts()
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    private func applyRemoteSelectionSwitchEffects(accountID: String) async throws {
        let accounts = try await accountsCoordinator.listAccounts()
        guard let matchingAccount = accounts.first(where: { $0.accountID == accountID }) else { return }
        _ = try await accountsCoordinator.switchAccountAndApplySettings(id: matchingAccount.id)
    }

    private func handleCurrentSelectionPushNotification() async {
        do {
            let result = try await pullCurrentSelectionForPushNotification()
            guard result.didUpdateSelection else { return }
            accounts = try await accountsCoordinator.listAccounts()
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    private func pullCloudAccountsForPushNotification() async throws -> AccountsCloudSyncPullResult {
        try await retryPullAfterPush(
            policy: .nearRealtime,
            operation: {
                try await pullCloudAccountsIfNeeded(failOnError: false)
            },
            stopWhen: { $0.didUpdateAccounts }
        )
    }

    private func pullCurrentSelectionForPushNotification() async throws -> CurrentAccountSelectionPullResult {
        guard let currentAccountSelectionSyncService else {
            return .noChange
        }

        let result = try await retryPullAfterPush(
            policy: .nearRealtime,
            operation: {
                try await currentAccountSelectionSyncService.pullRemoteSelectionIfNeeded()
            },
            stopWhen: { $0.didUpdateSelection }
        )

        if result.changedCurrentAccount,
           backgroundRefreshPolicy.applyRemoteSelectionSwitchEffects,
           let remoteAccountID = result.accountID {
            try await applyRemoteSelectionSwitchEffects(accountID: remoteAccountID)
        }

        return result
    }

    private func retryPullAfterPush<Result>(
        policy: CloudPushPullRetryPolicy,
        operation: () async throws -> Result,
        stopWhen: (Result) -> Bool
    ) async throws -> Result {
        var latest = try await operation()
        if stopWhen(latest) {
            return latest
        }

        guard !policy.retryIntervals.isEmpty else {
            return latest
        }

        for retryInterval in policy.retryIntervals {
            if Task.isCancelled {
                break
            }
            try? await Task.sleep(for: retryInterval)
            latest = try await operation()
            if stopWhen(latest) {
                break
            }
        }

        return latest
    }
}
