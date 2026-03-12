import Foundation
import Combine

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

    @Published var preferredPortText = "8787"
    @Published var cloudflaredHostname = ""
    @Published var cloudflaredUseHTTP2 = false
    @Published var autoStartProxy = false
    @Published var publicAccessEnabled = false

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

    func load() async {
        loading = true
        defer { loading = false }

        await refreshStatusOnly()

        do {
            let settings = try await settingsCoordinator.currentSettings()
            remoteServers = settings.remoteServers
            autoStartProxy = settings.autoStartApiProxy
            publicAccessEnabled = cloudflaredStatus.running
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
            cloudflaredStatus = try await coordinator.installCloudflared()
            await refreshStatusOnly()
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.cloudflared_installed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startCloudflared() async {
        guard let port = proxyStatus.port else {
            notice = NoticeMessage(style: .error, text: L10n.tr("proxy.notice.start_api_proxy_first"))
            return
        }

        loading = true
        defer { loading = false }

        do {
            let input = StartCloudflaredTunnelInput(
                apiProxyPort: port,
                useHTTP2: cloudflaredUseHTTP2,
                mode: cloudflaredHostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .quick : .named,
                hostname: cloudflaredHostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cloudflaredHostname
            )
            cloudflaredStatus = try await coordinator.startCloudflared(input: input)
            publicAccessEnabled = true
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.cloudflared_started"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopCloudflared() async {
        loading = true
        defer { loading = false }

        cloudflaredStatus = await coordinator.stopCloudflared()
        publicAccessEnabled = false
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.cloudflared_stopped"))
    }

    func refreshCloudflared() async {
        cloudflaredStatus = await coordinator.refreshCloudflared()
        publicAccessEnabled = cloudflaredStatus.running
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
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.server_draft_added"))
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
        let status = await coordinator.remoteStatus(server: server)
        remoteStatuses[server.id] = status
    }

    func deployRemote(server: RemoteServerConfig) async {
        loading = true
        defer { loading = false }

        do {
            let status = try await coordinator.deployRemote(server: server)
            remoteStatuses[server.id] = status
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_deploy_done_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startRemote(server: RemoteServerConfig) async {
        loading = true
        defer { loading = false }

        do {
            let status = try await coordinator.startRemote(server: server)
            remoteStatuses[server.id] = status
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_started_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopRemote(server: RemoteServerConfig) async {
        loading = true
        defer { loading = false }

        do {
            let status = try await coordinator.stopRemote(server: server)
            remoteStatuses[server.id] = status
            notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.remote_stopped_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func readRemoteLogs(server: RemoteServerConfig) async {
        loading = true
        defer { loading = false }

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
        cloudflaredStatus = pair.1
        publicAccessEnabled = cloudflaredStatus.running
    }
}
