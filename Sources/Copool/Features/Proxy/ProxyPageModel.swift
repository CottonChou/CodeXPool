import Foundation
import Combine

enum RemoteServerAction: Equatable {
    case save
    case remove
    case refresh
    case deploy
    case start
    case stop
    case logs
}

@MainActor
final class ProxyPageModel: ObservableObject {
    private let coordinator: ProxyCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()
    private var didRunLaunchBootstrap = false

    @Published var proxyStatus: ApiProxyStatus = .idle
    @Published var cloudflaredStatus: CloudflaredStatus = .idle
    @Published var remoteServers: [RemoteServerConfig] = []
    @Published var remoteStatuses: [String: RemoteProxyStatus] = [:]
    @Published var remoteLogs: [String: String] = [:]
    @Published var remoteActions: [String: RemoteServerAction] = [:]

    @Published var preferredPortText = "8787"
    @Published var cloudflaredTunnelMode: CloudflaredTunnelMode = .quick
    @Published var cloudflaredNamedInput = NamedCloudflaredTunnelInput(
        apiToken: "",
        accountID: "",
        zoneID: "",
        hostname: ""
    )
    @Published var cloudflaredUseHTTP2 = false
    @Published var autoStartProxy = false
    @Published var publicAccessEnabled = false
    @Published var apiProxySectionExpanded = true
    @Published var cloudflaredSectionExpanded = false

    @Published var loading = false
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }

    init(coordinator: ProxyCoordinator, settingsCoordinator: SettingsCoordinator) {
        self.coordinator = coordinator
        self.settingsCoordinator = settingsCoordinator
    }

    var cloudflaredExpanded: Bool {
        cloudflaredSectionExpanded
    }

    var canStartCloudflared: Bool {
        guard !loading else { return false }
        guard proxyStatus.running, proxyStatus.port != nil else { return false }
        guard cloudflaredStatus.installed, !cloudflaredStatus.running else { return false }
        if cloudflaredTunnelMode == .quick {
            return true
        }
        return cloudflaredNamedInputReady
    }

    var canEditCloudflaredInput: Bool {
        !loading && !cloudflaredStatus.running
    }

    var cloudflaredNamedInputReady: Bool {
        !cloudflaredNamedInput.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudflaredNamedInput.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudflaredNamedInput.zoneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudflaredNamedInput.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bootstrapOnAppLaunch(using settings: AppSettings) async {
        guard !didRunLaunchBootstrap else { return }
        didRunLaunchBootstrap = true

        autoStartProxy = settings.autoStartApiProxy
        await refreshStatusOnly()

        guard settings.autoStartApiProxy, !proxyStatus.running else { return }

        do {
            proxyStatus = try await coordinator.startProxy(preferredPort: nil)
            await refreshStatusOnly()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func collapseForTabEntry() {
        apiProxySectionExpanded = false
        cloudflaredSectionExpanded = false
    }

    func load() async {
        loading = true
        defer { loading = false }

        await refreshStatusOnly()

        do {
            let settings = try await settingsCoordinator.currentSettings()
            remoteServers = settings.remoteServers
            autoStartProxy = settings.autoStartApiProxy
            await refreshAllRemoteStatuses()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshStatus() async {
        loading = true
        defer { loading = false }
        await refreshStatusOnly()
    }

    func startProxy() async {
        loading = true
        defer { loading = false }

        let preferredPort = Int(preferredPortText)

        do {
            proxyStatus = try await coordinator.startProxy(preferredPort: preferredPort)
            await refreshStatusOnly()
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.api_proxy_started"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopProxy() async {
        loading = true
        defer { loading = false }

        proxyStatus = await coordinator.stopProxy()
        await refreshStatusOnly()
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.api_proxy_stopped"))
    }

    func refreshAPIKey() async {
        loading = true
        defer { loading = false }

        do {
            proxyStatus = try await coordinator.refreshAPIKey()
            await refreshStatusOnly()
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.api_key_refreshed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func installCloudflared() async {
        loading = true
        defer { loading = false }

        do {
            let status = try await coordinator.installCloudflared()
            applyCloudflaredStatus(status)
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.cloudflared_installed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startCloudflared() async {
        loading = true
        defer { loading = false }

        do {
            let input = try buildCloudflaredStartInput()
            let status = try await coordinator.startCloudflared(input: input)
            applyCloudflaredStatus(status)
            publicAccessEnabled = true
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.cloudflared_started"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopCloudflared() async {
        loading = true
        defer { loading = false }

        let status = await coordinator.stopCloudflared()
        applyCloudflaredStatus(status)
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.cloudflared_stopped"))
    }

    func refreshCloudflared() async {
        let status = await coordinator.refreshCloudflared()
        applyCloudflaredStatus(status)
    }

    func setPublicAccessEnabled(_ enabled: Bool) async {
        if enabled {
            publicAccessEnabled = true
            cloudflaredSectionExpanded = true
            return
        }
        publicAccessEnabled = false
        guard cloudflaredStatus.running else { return }
        await stopCloudflared()
    }

    func setAutoStartProxy(_ value: Bool) async {
        do {
            let updated = try await settingsCoordinator.updateSettings(AppSettingsPatch(autoStartApiProxy: value))
            autoStartProxy = updated.autoStartApiProxy
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.auto_start_updated"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func addRemoteServer() async {
        do {
            let draft = RemoteServerConfig(
                id: UUID().uuidString,
                label: "new-server",
                host: "",
                sshPort: 22,
                sshUser: "root",
                authMode: "keyPath",
                identityFile: nil,
                privateKey: nil,
                password: nil,
                remoteDir: "/opt/codex-tools",
                listenPort: 8787
            )
            let merged = remoteServers + [draft]
            let updated = try await settingsCoordinator.updateSettings(AppSettingsPatch(remoteServers: merged))
            remoteServers = updated.remoteServers
            notice = NoticeMessage(style: .success, text: L10n.tr("settings.notice.remote_servers_saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveRemoteServer(_ server: RemoteServerConfig) async {
        remoteActions[server.id] = .save
        defer { remoteActions.removeValue(forKey: server.id) }
        do {
            let normalized = normalizeRemoteServer(server)
            var merged = remoteServers
            if let index = merged.firstIndex(where: { $0.id == normalized.id }) {
                merged[index] = normalized
            } else {
                merged.append(normalized)
            }
            let updated = try await settingsCoordinator.updateSettings(AppSettingsPatch(remoteServers: merged))
            remoteServers = updated.remoteServers
            notice = NoticeMessage(style: .success, text: L10n.tr("settings.notice.remote_servers_saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func removeRemoteServer(id: String) async {
        remoteActions[id] = .remove
        defer { remoteActions.removeValue(forKey: id) }
        do {
            let merged = remoteServers.filter { $0.id != id }
            let updated = try await settingsCoordinator.updateSettings(AppSettingsPatch(remoteServers: merged))
            remoteServers = updated.remoteServers
            remoteStatuses.removeValue(forKey: id)
            remoteLogs.removeValue(forKey: id)
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_server_removed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshAllRemoteStatuses() async {
        for server in remoteServers {
            let status = await coordinator.remoteStatus(server: server)
            remoteStatuses[server.id] = status
        }
    }

    func refreshRemote(server: RemoteServerConfig) async {
        remoteActions[server.id] = .refresh
        defer { remoteActions.removeValue(forKey: server.id) }
        let status = await coordinator.remoteStatus(server: server)
        remoteStatuses[server.id] = status
    }

    func deployRemote(server: RemoteServerConfig) async {
        remoteActions[server.id] = .deploy
        defer { remoteActions.removeValue(forKey: server.id) }
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.remote_deploying_format", server.label))

        do {
            let status = try await coordinator.deployRemote(server: server)
            remoteStatuses[server.id] = status
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_deploy_done_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startRemote(server: RemoteServerConfig) async {
        remoteActions[server.id] = .start
        defer { remoteActions.removeValue(forKey: server.id) }

        do {
            let status = try await coordinator.startRemote(server: server)
            remoteStatuses[server.id] = status
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_started_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopRemote(server: RemoteServerConfig) async {
        remoteActions[server.id] = .stop
        defer { remoteActions.removeValue(forKey: server.id) }

        do {
            let status = try await coordinator.stopRemote(server: server)
            remoteStatuses[server.id] = status
            notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.remote_stopped_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func readRemoteLogs(server: RemoteServerConfig) async {
        remoteActions[server.id] = .logs
        defer { remoteActions.removeValue(forKey: server.id) }

        do {
            let logs = try await coordinator.readRemoteLogs(server: server, lines: 120)
            remoteLogs[server.id] = logs
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func refreshStatusOnly() async {
        let pair = await coordinator.loadStatus()
        proxyStatus = pair.0
        applyCloudflaredStatus(pair.1)
    }

    private func applyCloudflaredStatus(_ status: CloudflaredStatus) {
        cloudflaredStatus = status
        cloudflaredUseHTTP2 = status.useHTTP2
        if let mode = status.tunnelMode {
            cloudflaredTunnelMode = mode
        }
        if let hostname = status.customHostname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hostname.isEmpty {
            cloudflaredNamedInput.hostname = hostname
        }
        if status.running {
            publicAccessEnabled = true
            cloudflaredSectionExpanded = true
        }
    }

    private func buildCloudflaredStartInput() throws -> StartCloudflaredTunnelInput {
        guard let port = proxyStatus.port else {
            throw AppError.invalidData(L10n.tr("proxy.notice.start_api_proxy_first"))
        }

        let named: NamedCloudflaredTunnelInput?
        if cloudflaredTunnelMode == .named {
            named = try normalizedNamedInput()
        } else {
            named = nil
        }

        return StartCloudflaredTunnelInput(
            apiProxyPort: port,
            useHTTP2: cloudflaredUseHTTP2,
            mode: cloudflaredTunnelMode,
            named: named
        )
    }

    private func normalizedNamedInput() throws -> NamedCloudflaredTunnelInput {
        let apiToken = cloudflaredNamedInput.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = cloudflaredNamedInput.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let zoneID = cloudflaredNamedInput.zoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostname = cloudflaredNamedInput.hostname
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        guard !apiToken.isEmpty, !accountID.isEmpty, !zoneID.isEmpty, !hostname.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.cloudflared.named_required_fields"))
        }
        guard hostname.contains(".") else {
            throw AppError.invalidData(L10n.tr("error.cloudflared.named_invalid_hostname"))
        }

        return NamedCloudflaredTunnelInput(
            apiToken: apiToken,
            accountID: accountID,
            zoneID: zoneID,
            hostname: hostname
        )
    }

    private func normalizeRemoteServer(_ server: RemoteServerConfig) -> RemoteServerConfig {
        var value = server
        value.id = value.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.id.isEmpty {
            value.id = UUID().uuidString
        }
        value.label = value.label.trimmingCharacters(in: .whitespacesAndNewlines)
        value.host = value.host.trimmingCharacters(in: .whitespacesAndNewlines)
        value.sshUser = value.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        value.remoteDir = value.remoteDir.trimmingCharacters(in: .whitespacesAndNewlines)
        value.identityFile = value.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.privateKey = value.privateKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.password = value.password?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
}
