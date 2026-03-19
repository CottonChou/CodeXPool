import Foundation

struct AccountsSnapshotFreshnessPolicy: Sendable {
    let remoteSnapshotFreshnessWindowSeconds: Int64

    init(remoteSnapshotFreshnessWindowSeconds: Int64 = 30) {
        self.remoteSnapshotFreshnessWindowSeconds = remoteSnapshotFreshnessWindowSeconds
    }

    func isRemoteSnapshotFresh(
        remoteSyncedAt: Int64?,
        now: Int64
    ) -> Bool {
        guard let remoteSyncedAt else {
            return false
        }
        return now - remoteSyncedAt <= remoteSnapshotFreshnessWindowSeconds
    }

    func shouldRefreshUsage(
        forceRefresh: Bool,
        remoteSyncedAt: Int64?,
        now: Int64
    ) -> Bool {
        if forceRefresh {
            return true
        }

        guard let remoteSyncedAt else {
            return true
        }

        return !isRemoteSnapshotFresh(remoteSyncedAt: remoteSyncedAt, now: now)
    }
}
