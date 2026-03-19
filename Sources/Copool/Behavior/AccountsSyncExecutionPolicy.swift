import Foundation

enum AccountsCloudSyncMode: Sendable {
    case disabled
    case pushLocalAccounts
    case pullRemoteAccounts
}

struct AccountsSyncExecutionDecision: Equatable, Sendable {
    let shouldRefreshLocalUsage: Bool
    let shouldPushLocalSnapshot: Bool

    static let noRefreshNoPush = AccountsSyncExecutionDecision(
        shouldRefreshLocalUsage: false,
        shouldPushLocalSnapshot: false
    )
}

struct AccountsSyncExecutionPolicy: Sendable {
    private let snapshotFreshnessPolicy: AccountsSnapshotFreshnessPolicy

    init(snapshotFreshnessPolicy: AccountsSnapshotFreshnessPolicy = AccountsSnapshotFreshnessPolicy()) {
        self.snapshotFreshnessPolicy = snapshotFreshnessPolicy
    }

    func decision(
        cloudSyncMode: AccountsCloudSyncMode,
        forceUsageRefresh: Bool,
        remoteSyncedAt: Int64?,
        now: Int64
    ) -> AccountsSyncExecutionDecision {
        let shouldRefreshByFreshness = snapshotFreshnessPolicy.shouldRefreshUsage(
            forceRefresh: forceUsageRefresh,
            remoteSyncedAt: remoteSyncedAt,
            now: now
        )

        switch cloudSyncMode {
        case .disabled:
            return AccountsSyncExecutionDecision(
                shouldRefreshLocalUsage: shouldRefreshByFreshness,
                shouldPushLocalSnapshot: false
            )
        case .pushLocalAccounts:
            return AccountsSyncExecutionDecision(
                shouldRefreshLocalUsage: shouldRefreshByFreshness,
                shouldPushLocalSnapshot: shouldRefreshByFreshness
            )
        case .pullRemoteAccounts:
            // iOS follows cloud snapshots by default. It can seed cloud once when no snapshot exists yet.
            let canBootstrapSeed = remoteSyncedAt == nil
            if !canBootstrapSeed {
                return .noRefreshNoPush
            }
            return AccountsSyncExecutionDecision(
                shouldRefreshLocalUsage: shouldRefreshByFreshness,
                shouldPushLocalSnapshot: shouldRefreshByFreshness
            )
        }
    }
}
