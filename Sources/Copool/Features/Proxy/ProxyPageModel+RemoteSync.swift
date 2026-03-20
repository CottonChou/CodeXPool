import Foundation
import Combine

extension ProxyPageModel {
    func startRemoteSnapshotSyncIfNeeded() {
        guard usesRemoteMacControl else { return }
        guard remoteSnapshotTask == nil else { return }

        remoteSnapshotTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: ProxySyncPolicy.RemoteControl.snapshotSyncInterval)
                await self.refreshRemoteSnapshot(showErrors: false)
            }
        }
    }

    func stopRemoteSnapshotSync() {
        remoteSnapshotTask?.cancel()
        remoteSnapshotTask = nil
    }

    func configureProxyPushHandlingIfNeeded() {
        guard proxyPushCancellable == nil else { return }

        proxyPushCancellable = NotificationCenter.default
            .publisher(for: .copoolProxyControlPushDidArrive)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refreshRemoteSnapshotAfterPush()
                }
            }
    }

    func configureLocalSnapshotHandlingIfNeeded() {
        guard runtimePlatform == .macOS else { return }
        guard localSnapshotCancellable == nil else { return }

        localSnapshotCancellable = NotificationCenter.default
            .publisher(for: .copoolLocalProxySnapshotDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let snapshot = notification.userInfo?[ProxyControlNotificationPayloadKey.snapshot] as? ProxyControlSnapshot else { return }
                self.applyRemoteSnapshot(snapshot)
            }
    }

    func ensureProxyPushSubscriptionIfNeeded() async {
        guard let proxyControlCloudSyncService else { return }
        do {
            try await proxyControlCloudSyncService.ensurePushSubscriptionIfNeeded()
        } catch {
            #if DEBUG
            // print("CloudKit proxy push subscription skipped:", error.localizedDescription)
            #endif
        }
    }

    @discardableResult
    func refreshRemoteSnapshot(showErrors: Bool) async -> Bool {
        guard let proxyControlCloudSyncService else { return false }

        do {
            if let snapshot = try await proxyControlCloudSyncService.pullRemoteSnapshot() {
                return applyRemoteSnapshot(snapshot)
            }
        } catch {
            if showErrors {
                notice = NoticeMessage(style: .error, text: error.localizedDescription)
            }
        }

        return false
    }

    @discardableResult
    func applyRemoteSnapshot(_ snapshot: ProxyControlSnapshot) -> Bool {
        lastAppliedRemoteSnapshot = snapshot
        lastHandledRemoteCommandID = snapshot.lastHandledCommandID
        lastRemoteCommandError = snapshot.lastCommandError
        lastAppliedRemoteSnapshotSyncedAt = snapshot.syncedAt
        lastAppliedRemoteStatusesSyncedAt = snapshot.remoteStatusesSyncedAt
        let nextState = ProxyRemoteSnapshotPresentationState(snapshot: snapshot)
        guard nextState != currentRemoteSnapshotPresentationState else {
            return false
        }

        setIfChanged(\.proxyStatus, nextState.proxyStatus)
        setIfChanged(\.preferredPortText, nextState.preferredPortText)
        setIfChanged(\.autoStartProxy, nextState.autoStartProxy)
        setIfChanged(\.cloudflaredStatus, nextState.cloudflaredStatus)
        setIfChanged(\.cloudflaredTunnelMode, nextState.cloudflaredTunnelMode)
        setIfChanged(\.cloudflaredUseHTTP2, nextState.cloudflaredUseHTTP2)
        setIfChanged(\.publicAccessEnabled, nextState.publicAccessEnabled)
        setIfChanged(\.remoteServers, nextState.remoteServers)
        setIfChanged(\.remoteStatuses, nextState.remoteStatuses)
        setIfChanged(\.remoteLogs, nextState.remoteLogs)
        if cloudflaredNamedInput.hostname != nextState.cloudflaredNamedHostname {
            cloudflaredNamedInput.hostname = nextState.cloudflaredNamedHostname
        }
        lastSyncedProxyConfiguration = currentProxyConfiguration
        return true
    }

    func acceptedAppliedRemoteSnapshot(
        for commandID: String,
        acceptance: ((ProxyControlSnapshot) -> Bool)? = nil
    ) -> ProxyControlSnapshot? {
        guard let snapshot = lastAppliedRemoteSnapshot else { return nil }
        let isAccepted = acceptance?(snapshot) ?? (snapshot.lastHandledCommandID == commandID)
        return isAccepted ? snapshot : nil
    }

    func shouldRequestRemoteSnapshotRefresh() -> Bool {
        guard let lastAppliedRemoteSnapshotSyncedAt else {
            return true
        }

        let now = dateProvider.unixMillisecondsNow()
        if now - lastAppliedRemoteSnapshotSyncedAt >= ProxySyncPolicy.RemoteControl.snapshotFreshnessWindowMilliseconds {
            return true
        }

        guard !remoteServers.isEmpty else {
            return false
        }

        guard let lastAppliedRemoteStatusesSyncedAt else {
            return true
        }
        return now - lastAppliedRemoteStatusesSyncedAt >= ProxySyncPolicy.RemoteControl.remoteStatusesFreshnessWindowMilliseconds
    }

    func requestRemoteSnapshotRefresh(
        showErrors: Bool,
        showLoading: Bool = false
    ) async {
        guard let proxyControlCloudSyncService else { return }

        if showLoading {
            loading = true
        }
        defer {
            if showLoading {
                loading = false
            }
        }

        let command = makeProxyControlCommand(
            sourceDeviceID: "ios-proxy-control",
            kind: .refreshStatus
        )

        do {
            try await proxyControlCloudSyncService.enqueueCommand(command)
            lastRemoteCommandID = command.id

            if let acknowledgedSnapshot = try await waitForRemoteCommandAck(command.id) {
                applyRemoteSnapshot(acknowledgedSnapshot)
            } else {
                await refreshRemoteSnapshot(showErrors: false)
            }
        } catch {
            if showErrors {
                notice = NoticeMessage(style: .error, text: error.localizedDescription)
            }
        }
    }

    private func refreshRemoteSnapshotAfterPush() async {
        let policy = CloudPushPullRetryPolicy.nearRealtime
        if await refreshRemoteSnapshot(showErrors: false) {
            return
        }

        for retryInterval in policy.retryIntervals {
            try? await Task.sleep(for: retryInterval)
            if await refreshRemoteSnapshot(showErrors: false) {
                return
            }
        }
    }

    private var currentRemoteSnapshotPresentationState: ProxyRemoteSnapshotPresentationState {
        ProxyRemoteSnapshotPresentationState(
            proxyStatus: proxyStatus,
            preferredPortText: preferredPortText,
            autoStartProxy: autoStartProxy,
            cloudflaredStatus: cloudflaredStatus,
            cloudflaredTunnelMode: cloudflaredTunnelMode,
            cloudflaredNamedHostname: cloudflaredNamedInput.hostname,
            cloudflaredUseHTTP2: cloudflaredUseHTTP2,
            publicAccessEnabled: publicAccessEnabled,
            remoteServers: remoteServers,
            remoteStatuses: remoteStatuses,
            remoteLogs: remoteLogs
        )
    }

    private func setIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<ProxyPageModel, Value>,
        _ newValue: Value
    ) {
        guard self[keyPath: keyPath] != newValue else { return }
        self[keyPath: keyPath] = newValue
    }
}
