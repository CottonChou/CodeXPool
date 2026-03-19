import XCTest
@testable import Copool

final class ProxyControlBridgeTests: XCTestCase {
    func testStartDoesNotRunBridgeLoopOnIOS() async throws {
        let cloudSyncService = SpyProxyControlCloudSyncService()
        let bridge = makeBridge(
            cloudSyncService: cloudSyncService,
            runtimePlatform: .iOS
        )

        await bridge.start()
        try? await Task.sleep(for: .milliseconds(150))
        await bridge.stop()

        let metrics = await cloudSyncService.readMetrics()
        XCTAssertEqual(metrics.ensurePushSubscriptionCallCount, 0)
        XCTAssertEqual(metrics.pushLocalSnapshotCallCount, 0)
        XCTAssertEqual(metrics.pullPendingCommandCallCount, 0)
    }

    func testStartRunsBridgeLoopOnMacOS() async throws {
        let cloudSyncService = SpyProxyControlCloudSyncService()
        let bridge = makeBridge(
            cloudSyncService: cloudSyncService,
            runtimePlatform: .macOS
        )

        await bridge.start()
        try? await Task.sleep(for: .milliseconds(150))
        await bridge.stop()

        let metrics = await cloudSyncService.readMetrics()
        XCTAssertGreaterThanOrEqual(metrics.ensurePushSubscriptionCallCount, 1)
        XCTAssertGreaterThanOrEqual(metrics.pullPendingCommandCallCount, 1)
        XCTAssertGreaterThanOrEqual(metrics.pushLocalSnapshotCallCount, 1)
    }

    private func makeBridge(
        cloudSyncService: ProxyControlCloudSyncServiceProtocol?,
        runtimePlatform: RuntimePlatform
    ) -> ProxyControlBridge {
        let proxyCoordinator = ProxyCoordinator(
            proxyService: StubProxyRuntimeService(),
            cloudflaredService: StubCloudflaredService(),
            remoteService: StubRemoteProxyService()
        )
        let settingsCoordinator = SettingsCoordinator(
            storeRepository: InMemoryAccountsStoreRepository(store: AccountsStore()),
            launchAtStartupService: StubLaunchAtStartupService()
        )

        return ProxyControlBridge(
            proxyCoordinator: proxyCoordinator,
            settingsCoordinator: settingsCoordinator,
            cloudSyncService: cloudSyncService,
            runtimePlatform: runtimePlatform
        )
    }
}

private struct CloudSyncMetrics {
    var ensurePushSubscriptionCallCount: Int
    var pushLocalSnapshotCallCount: Int
    var pullPendingCommandCallCount: Int
}

private actor SpyProxyControlCloudSyncService: ProxyControlCloudSyncServiceProtocol {
    private var ensurePushSubscriptionCallCount = 0
    private var pushLocalSnapshotCallCount = 0
    private var pullPendingCommandCallCount = 0

    func pushLocalSnapshot(_ snapshot: ProxyControlSnapshot) async throws {
        _ = snapshot
        pushLocalSnapshotCallCount += 1
    }

    func pullRemoteSnapshot() async throws -> ProxyControlSnapshot? {
        nil
    }

    func enqueueCommand(_ command: ProxyControlCommand) async throws {
        _ = command
    }

    func pullPendingCommand() async throws -> ProxyControlCommand? {
        pullPendingCommandCallCount += 1
        return nil
    }

    func ensurePushSubscriptionIfNeeded() async throws {
        ensurePushSubscriptionCallCount += 1
    }

    func readMetrics() -> CloudSyncMetrics {
        CloudSyncMetrics(
            ensurePushSubscriptionCallCount: ensurePushSubscriptionCallCount,
            pushLocalSnapshotCallCount: pushLocalSnapshotCallCount,
            pullPendingCommandCallCount: pullPendingCommandCallCount
        )
    }
}

private final class InMemoryAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store: AccountsStore

    init(store: AccountsStore) {
        self.store = store
    }

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

private struct StubLaunchAtStartupService: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) throws {
        _ = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        _ = enabled
    }
}

private struct StubProxyRuntimeService: ProxyRuntimeService {
    func status() async -> ApiProxyStatus { .idle }

    func start(preferredPort: Int?) async throws -> ApiProxyStatus {
        _ = preferredPort
        return .idle
    }

    func stop() async -> ApiProxyStatus { .idle }

    func refreshAPIKey() async throws -> ApiProxyStatus { .idle }

    func syncAccountsStore() async throws {}
}

private struct StubCloudflaredService: CloudflaredServiceProtocol {
    func status() async -> CloudflaredStatus { .idle }

    func install() async throws -> CloudflaredStatus { .idle }

    func start(_ input: StartCloudflaredTunnelInput) async throws -> CloudflaredStatus {
        _ = input
        return .idle
    }

    func stop() async -> CloudflaredStatus { .idle }
}

private struct StubRemoteProxyService: RemoteProxyServiceProtocol {
    func status(server: RemoteServerConfig) async -> RemoteProxyStatus {
        _ = server
        return RemoteProxyStatus(
            installed: false,
            serviceInstalled: false,
            running: false,
            enabled: false,
            serviceName: "",
            pid: nil,
            baseURL: "",
            apiKey: nil,
            lastError: nil
        )
    }

    func deploy(server: RemoteServerConfig) async throws -> RemoteProxyStatus {
        await status(server: server)
    }

    func start(server: RemoteServerConfig) async throws -> RemoteProxyStatus {
        await status(server: server)
    }

    func stop(server: RemoteServerConfig) async throws -> RemoteProxyStatus {
        await status(server: server)
    }

    func readLogs(server: RemoteServerConfig, lines: Int) async throws -> String {
        _ = server
        _ = lines
        return ""
    }
}
