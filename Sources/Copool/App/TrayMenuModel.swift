import Foundation
import Combine

@MainActor
final class TrayMenuModel: ObservableObject {
    private let accountsCoordinator: AccountsCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private var refreshTask: Task<Void, Never>?

    @Published var accounts: [AccountSummary] = []
    @Published var mode: TrayUsageDisplayMode = .remaining
    @Published var notice: String?

    init(accountsCoordinator: AccountsCoordinator, settingsCoordinator: SettingsCoordinator) {
        self.accountsCoordinator = accountsCoordinator
        self.settingsCoordinator = settingsCoordinator
    }

    func startBackgroundRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow(forceUsageRefresh: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self.refreshNow(forceUsageRefresh: true)
            }
        }
    }

    func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit {
        refreshTask?.cancel()
    }

    func refreshNow(forceUsageRefresh: Bool) async {
        do {
            let settings = try await settingsCoordinator.currentSettings()
            applySettings(settings)

            if forceUsageRefresh {
                accounts = try await accountsCoordinator.refreshAllUsage()
            } else {
                accounts = try await accountsCoordinator.listAccounts()
            }
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func applySettings(_ settings: AppSettings) {
        mode = settings.trayUsageDisplayMode
    }

    var title: String {
        guard mode != .hidden else { return L10n.tr("tray.title.app") }
        guard let current = accounts.first(where: { $0.isCurrent }) else {
            return L10n.tr("tray.title.placeholder")
        }

        let five = percent(modeValue(window: current.usage?.fiveHour))
        let week = percent(modeValue(window: current.usage?.oneWeek))
        return L10n.tr("tray.title.format", five, week)
    }

    func accountLine(_ account: AccountSummary) -> String {
        let prefix = account.isCurrent ? L10n.tr("tray.account.current_prefix") : ""
        guard mode != .hidden else {
            return "\(prefix)\(account.label)"
        }

        let five = percent(modeValue(window: account.usage?.fiveHour))
        let week = percent(modeValue(window: account.usage?.oneWeek))
        return L10n.tr("tray.account.line.format", prefix, account.label, five, week)
    }

    private func modeValue(window: UsageWindow?) -> Double? {
        guard let window else { return nil }
        switch mode {
        case .remaining:
            return max(0, 100 - window.usedPercent)
        case .used:
            return max(0, min(100, window.usedPercent))
        case .hidden:
            return nil
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }
}
