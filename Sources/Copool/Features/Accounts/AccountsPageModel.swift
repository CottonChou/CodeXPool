import Foundation
import Combine

@MainActor
final class AccountsPageModel: ObservableObject {
    private let coordinator: AccountsCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()

    @Published var state: ViewState<[AccountSummary]> = .loading
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }
    @Published var isRefreshing = false
    @Published var isImporting = false
    @Published var isAdding = false
    @Published var switchingAccountID: String?
    @Published private(set) var collapsedAccountIDs: Set<String> = []

    init(coordinator: AccountsCoordinator) {
        self.coordinator = coordinator
    }

    func loadIfNeeded() async {
        if case .loading = state {
            await load()
        }
    }

    func load() async {
        do {
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    func importCurrentAuth() async {
        isImporting = true
        defer { isImporting = false }

        do {
            let imported = try await coordinator.importCurrentAuthAccount(customLabel: nil)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.imported_format", imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func addAccountViaLogin() async {
        isAdding = true
        defer { isAdding = false }

        do {
            let imported = try await coordinator.addAccountViaLogin(customLabel: nil)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.imported_new_format", imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshUsage() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let accounts = try await coordinator.refreshAllUsage()
            applyAccounts(accounts)
            notice = NoticeMessage(style: .info, text: L10n.tr("accounts.notice.usage_refreshed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteAccount(id: String) async {
        do {
            try await coordinator.deleteAccount(id: id)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            notice = NoticeMessage(style: .info, text: L10n.tr("accounts.notice.account_deleted"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveTeamAlias(id: String, alias: String?) async {
        do {
            _ = try await coordinator.updateTeamAlias(id: id, alias: alias)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.team_name_updated"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func switchAccount(id: String) async {
        switchingAccountID = id
        defer { switchingAccountID = nil }

        do {
            let execution = try await coordinator.switchAccountAndApplySettings(id: id)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            notice = buildSwitchNotice(execution: execution)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func smartSwitch() async {
        do {
            let accountsBefore = try await coordinator.listAccounts()
            let sorted = AccountRanking.sortByRemaining(accountsBefore)
            guard let best = sorted.first else {
                notice = NoticeMessage(style: .info, text: L10n.tr("accounts.notice.no_switch_target"))
                return
            }
            if best.isCurrent {
                notice = NoticeMessage(style: .info, text: L10n.tr("accounts.notice.already_best"))
                return
            }

            let execution = try await coordinator.switchAccountAndApplySettings(id: best.id)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            var switchNotice = buildSwitchNotice(execution: execution)
            switchNotice.text = L10n.tr("accounts.notice.smart_switched_prefix_format", best.label, switchNotice.text)
            notice = switchNotice
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func isAccountCollapsed(_ id: String) -> Bool {
        collapsedAccountIDs.contains(id)
    }

    var areAllAccountsCollapsed: Bool {
        guard case .content(let accounts) = state else { return false }
        let ids = Set(accounts.map(\.id))
        guard !ids.isEmpty else { return false }
        return collapsedAccountIDs.isSuperset(of: ids)
    }

    func toggleAllAccountsCollapsed() {
        guard case .content(let accounts) = state else { return }
        let ids = Set(accounts.map(\.id))
        guard !ids.isEmpty else {
            collapsedAccountIDs = []
            return
        }
        collapsedAccountIDs = collapsedAccountIDs.isSuperset(of: ids) ? [] : ids
    }

    static func makeViewState(accounts: [AccountSummary]) -> ViewState<[AccountSummary]> {
        let sorted = AccountRanking.sortByRemaining(accounts)
        if sorted.isEmpty {
            return .empty(message: L10n.tr("accounts.empty.message.no_accounts"))
        }
        return .content(sorted)
    }

    private func buildSwitchNotice(execution: SwitchAccountExecutionResult) -> NoticeMessage {
        var style: NoticeStyle = .success
        var segments: [String] = []

        if execution.usedFallbackCLI {
            style = .info
            segments.append(L10n.tr("accounts.notice.switch_done_fallback"))
        } else {
            segments.append(L10n.tr("accounts.notice.switch_done"))
        }

        if let syncError = execution.opencodeSyncError, !syncError.isEmpty {
            style = .error
            segments.append(L10n.tr("accounts.notice.sync_failed_format", syncError))
        } else if execution.opencodeSynced {
            segments.append(L10n.tr("accounts.notice.sync_done"))
        }

        if let restartError = execution.editorRestartError, !restartError.isEmpty {
            style = .error
            segments.append(L10n.tr("accounts.notice.editor_restart_failed_format", restartError))
        } else if !execution.restartedEditorApps.isEmpty {
            let names = execution.restartedEditorApps.map(\.rawValue).joined(separator: " / ")
            segments.append(L10n.tr("accounts.notice.editor_restarted_format", names))
        }

        return NoticeMessage(style: style, text: segments.joined(separator: " · "))
    }

    private func applyAccounts(_ accounts: [AccountSummary]) {
        let sorted = AccountRanking.sortByRemaining(accounts)
        let availableIDs = Set(sorted.map(\.id))
        collapsedAccountIDs = collapsedAccountIDs.intersection(availableIDs)
        if sorted.isEmpty {
            state = .empty(message: L10n.tr("accounts.empty.message.no_accounts"))
        } else {
            state = .content(sorted)
        }
    }
}
