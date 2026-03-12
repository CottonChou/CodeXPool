import Foundation
import Combine

@MainActor
final class SettingsPageModel: ObservableObject {
    private let settingsCoordinator: SettingsCoordinator
    private let editorAppService: EditorAppServiceProtocol
    private let onSettingsUpdated: @MainActor (AppSettings) -> Void
    private let noticeScheduler = NoticeAutoDismissScheduler()

    @Published var settings: AppSettings = .defaultValue
    @Published var installedEditorApps: [InstalledEditorApp] = []
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }
    private var hasLoaded = false

    @Published var remoteServersJSON = "[]"

    init(
        settingsCoordinator: SettingsCoordinator,
        editorAppService: EditorAppServiceProtocol,
        onSettingsUpdated: @escaping @MainActor (AppSettings) -> Void = { _ in }
    ) {
        self.settingsCoordinator = settingsCoordinator
        self.editorAppService = editorAppService
        self.onSettingsUpdated = onSettingsUpdated
    }

    func loadIfNeeded() async {
        if !hasLoaded {
            await load()
        }
    }

    func load() async {
        do {
            settings = try await settingsCoordinator.currentSettings()
            remoteServersJSON = encodeRemoteServers(settings.remoteServers)
            installedEditorApps = editorAppService.listInstalledApps()
            onSettingsUpdated(settings)
            hasLoaded = true
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func setLaunchAtStartup(_ value: Bool) {
        Task { await update(AppSettingsPatch(launchAtStartup: value)) }
    }

    func setLaunchAfterSwitch(_ value: Bool) {
        Task { await update(AppSettingsPatch(launchCodexAfterSwitch: value)) }
    }

    func setAutoStartProxy(_ value: Bool) {
        Task { await update(AppSettingsPatch(autoStartApiProxy: value)) }
    }

    func setLocale(_ value: String) {
        Task { await update(AppSettingsPatch(locale: value)) }
    }

    func setTrayUsageDisplayMode(_ mode: TrayUsageDisplayMode) {
        Task { await update(AppSettingsPatch(trayUsageDisplayMode: mode)) }
    }

    func setSyncOpencodeOpenaiAuth(_ value: Bool) {
        Task { await update(AppSettingsPatch(syncOpencodeOpenaiAuth: value)) }
    }

    func setRestartEditorsOnSwitch(_ value: Bool) {
        if value && settings.restartEditorTargets.isEmpty, let first = installedEditorApps.first?.id {
            Task {
                await update(
                    AppSettingsPatch(
                        restartEditorsOnSwitch: true,
                        restartEditorTargets: [first]
                    )
                )
            }
            return
        }
        Task { await update(AppSettingsPatch(restartEditorsOnSwitch: value)) }
    }

    func setRestartEditorTarget(_ target: EditorAppID?) {
        let values = target.map { [$0] } ?? []
        Task { await update(AppSettingsPatch(restartEditorTargets: values), successText: L10n.tr("settings.notice.restart_target_updated")) }
    }

    func saveRemoteServersJSON() async {
        do {
            let servers = try decodeRemoteServers(remoteServersJSON)
            await update(AppSettingsPatch(remoteServers: servers), successText: L10n.tr("settings.notice.remote_servers_saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func update(_ patch: AppSettingsPatch, successText: String = L10n.tr("settings.notice.updated")) async {
        do {
            settings = try await settingsCoordinator.updateSettings(patch)
            remoteServersJSON = encodeRemoteServers(settings.remoteServers)
            onSettingsUpdated(settings)
            notice = NoticeMessage(style: .success, text: successText)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func encodeRemoteServers(_ servers: [RemoteServerConfig]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(servers),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private func decodeRemoteServers(_ raw: String) throws -> [RemoteServerConfig] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8) else {
            throw AppError.invalidData(L10n.tr("settings.error.remote_servers_json_utf8"))
        }

        do {
            return try JSONDecoder().decode([RemoteServerConfig].self, from: data)
        } catch {
            throw AppError.invalidData(L10n.tr("settings.error.remote_servers_json_decode_format", error.localizedDescription))
        }
    }
}
