import Foundation
import Combine

actor ProxyControlBridge {
    private enum Constants {
        static let syncInterval: Duration = .seconds(2)
    }

    private let proxyCoordinator: ProxyCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let cloudSyncService: ProxyControlCloudSyncServiceProtocol?
    private let dateProvider: DateProviding
    private let sourceDeviceID: String

    private var loopTask: Task<Void, Never>?
    private var lastHandledCommandID: String?
    private var lastCommandError: String?
    private var remoteLogs: [String: String] = [:]
    private var pushCancellable: AnyCancellable?

    init(
        proxyCoordinator: ProxyCoordinator,
        settingsCoordinator: SettingsCoordinator,
        cloudSyncService: ProxyControlCloudSyncServiceProtocol?,
        dateProvider: DateProviding = SystemDateProvider(),
        sourceDeviceID: String = "macos-proxy-bridge"
    ) {
        self.proxyCoordinator = proxyCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.cloudSyncService = cloudSyncService
        self.dateProvider = dateProvider
        self.sourceDeviceID = sourceDeviceID
    }

    func start() {
        guard loopTask == nil else { return }
        configurePushHandlingIfNeeded()
        Task {
            do {
                try await cloudSyncService?.ensurePushSubscriptionIfNeeded()
            } catch {
                #if DEBUG
                // print("CloudKit proxy push subscription skipped:", error.localizedDescription)
                #endif
            }
        }
        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        pushCancellable = nil
    }

    func handlePushNotification() async {
        do {
            try await processPendingCommandIfNeeded()
            try await publishSnapshot()
        } catch {
            #if DEBUG
            // print("Proxy control push handling skipped:", error.localizedDescription)
            #endif
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await processPendingCommandIfNeeded()
                try await publishSnapshot()
            } catch {
                #if DEBUG
                // print("Proxy control bridge skipped:", error.localizedDescription)
                #endif
            }

            try? await Task.sleep(for: Constants.syncInterval)
        }
    }

    private func configurePushHandlingIfNeeded() {
        guard pushCancellable == nil else { return }

        pushCancellable = NotificationCenter.default
            .publisher(for: .copoolProxyControlPushDidArrive)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.handlePushNotification()
                }
            }
    }

    private func publishSnapshot() async throws {
        guard let cloudSyncService else { return }
        let snapshot = try await buildSnapshot()
        try await cloudSyncService.pushLocalSnapshot(snapshot)
    }

    private func processPendingCommandIfNeeded() async throws {
        guard let cloudSyncService else { return }
        guard let command = try await cloudSyncService.pullPendingCommand() else { return }
        guard command.id != lastHandledCommandID else { return }

        do {
            try await execute(command)
            lastHandledCommandID = command.id
            lastCommandError = nil
        } catch {
            lastHandledCommandID = command.id
            lastCommandError = error.localizedDescription
        }

        try await publishSnapshot()
    }

    private func buildSnapshot() async throws -> ProxyControlSnapshot {
        let settings = try await settingsCoordinator.currentSettings()
        let pair = await proxyCoordinator.loadStatus()
        let proxyStatus = pair.0
        let cloudflaredStatus = pair.1

        var remoteStatuses: [String: RemoteProxyStatus] = [:]
        for server in settings.remoteServers {
            remoteStatuses[server.id] = await proxyCoordinator.remoteStatus(server: server)
        }

        return ProxyControlSnapshot(
            syncedAt: dateProvider.unixMillisecondsNow(),
            sourceDeviceID: sourceDeviceID,
            proxyStatus: proxyStatus,
            preferredProxyPort: proxyStatus.port ?? RemoteServerConfiguration.defaultProxyPort,
            autoStartProxy: settings.autoStartApiProxy,
            cloudflaredStatus: cloudflaredStatus,
            cloudflaredTunnelMode: cloudflaredStatus.tunnelMode ?? .quick,
            cloudflaredNamedInput: NamedCloudflaredTunnelInput(
                apiToken: "",
                accountID: "",
                zoneID: "",
                hostname: cloudflaredStatus.customHostname ?? ""
            ),
            cloudflaredUseHTTP2: cloudflaredStatus.useHTTP2,
            publicAccessEnabled: cloudflaredStatus.running,
            remoteServers: settings.remoteServers,
            remoteStatuses: remoteStatuses,
            remoteLogs: remoteLogs,
            lastHandledCommandID: lastHandledCommandID,
            lastCommandError: lastCommandError
        )
    }

    private func execute(_ command: ProxyControlCommand) async throws {
        switch command.kind {
        case .refreshStatus:
            return
        case .startProxy:
            _ = try await proxyCoordinator.startProxy(preferredPort: command.preferredProxyPort)
        case .stopProxy:
            _ = await proxyCoordinator.stopProxy()
        case .refreshAPIKey:
            _ = try await proxyCoordinator.refreshAPIKey()
        case .setAutoStartProxy:
            _ = try await settingsCoordinator.updateSettings(
                AppSettingsPatch(autoStartApiProxy: command.autoStartProxy ?? false)
            )
        case .installCloudflared:
            _ = try await proxyCoordinator.installCloudflared()
        case .startCloudflared:
            guard let input = command.cloudflaredInput else {
                throw AppError.invalidData("Missing cloudflared input.")
            }
            _ = try await proxyCoordinator.startCloudflared(input: input)
        case .stopCloudflared:
            _ = await proxyCoordinator.stopCloudflared()
        case .refreshCloudflared:
            _ = await proxyCoordinator.refreshCloudflared()
        case .addRemoteServer:
            let draft = command.remoteServer ?? RemoteServerConfiguration.makeDraft()
            let settings = try await settingsCoordinator.currentSettings()
            _ = try await settingsCoordinator.updateSettings(
                AppSettingsPatch(
                    remoteServers: settings.remoteServers + [RemoteServerConfiguration.normalize(draft)]
                )
            )
        case .saveRemoteServer:
            guard let remoteServer = command.remoteServer else {
                throw AppError.invalidData("Missing remote server payload.")
            }
            let settings = try await settingsCoordinator.currentSettings()
            let merged = RemoteServerConfiguration.upsert(remoteServer, into: settings.remoteServers)
            _ = try await settingsCoordinator.updateSettings(
                AppSettingsPatch(remoteServers: merged)
            )
        case .removeRemoteServer:
            guard let id = command.remoteServerID else {
                throw AppError.invalidData("Missing remote server id.")
            }
            let settings = try await settingsCoordinator.currentSettings()
            let merged = settings.remoteServers.filter { $0.id != id }
            _ = try await settingsCoordinator.updateSettings(
                AppSettingsPatch(remoteServers: merged)
            )
            remoteLogs.removeValue(forKey: id)
        case .refreshRemote:
            guard let server = try await serverForCommand(command) else { return }
            _ = await proxyCoordinator.remoteStatus(server: server)
        case .deployRemote:
            guard let server = try await serverForCommand(command) else { return }
            _ = try await proxyCoordinator.deployRemote(server: server)
        case .startRemote:
            guard let server = try await serverForCommand(command) else { return }
            _ = try await proxyCoordinator.startRemote(server: server)
        case .stopRemote:
            guard let server = try await serverForCommand(command) else { return }
            _ = try await proxyCoordinator.stopRemote(server: server)
        case .readRemoteLogs:
            guard let server = try await serverForCommand(command) else { return }
            let logs = try await proxyCoordinator.readRemoteLogs(
                server: server,
                lines: command.logLines ?? 120
            )
            remoteLogs[server.id] = logs
        }
    }

    private func serverForCommand(_ command: ProxyControlCommand) async throws -> RemoteServerConfig? {
        guard let id = command.remoteServerID else {
            throw AppError.invalidData("Missing remote server id.")
        }
        let settings = try await settingsCoordinator.currentSettings()
        return settings.remoteServers.first(where: { $0.id == id })
    }
}
