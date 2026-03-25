import Foundation
import OSLog

extension AccountsPageModel {
    private var authFlowLogger: Logger {
        Logger(subsystem: "Copool", category: "AccountsPageAuthFlow")
    }

    func importCurrentAuth() async {
        guard runtimePlatform == .macOS else {
            notice = NoticeMessage(style: .error, text: PlatformCapabilities.unsupportedOperationMessage)
            return
        }
        isImporting = true
        defer { isImporting = false }

        do {
            let imported = try await coordinator.importCurrentAuthAccount(customLabel: nil)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts, preferredSourceAccountID: imported.id)
            publishAndSyncLocalAccountsMutation(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.imported_format", imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func addAccountViaLogin() async {
        isAdding = true
        defer { isAdding = false }

        do {
            authFlowLogger.log("AccountsPageModel.addAccountViaLogin started")
            AuthFlowDebugLog.write("AccountsPageAuthFlow", "AccountsPageModel.addAccountViaLogin started")
            let imported = try await coordinator.addAccountViaLogin(customLabel: nil)
            authFlowLogger.log("AccountsPageModel.addAccountViaLogin coordinator returned \(imported.accountID, privacy: .public)")
            AuthFlowDebugLog.write("AccountsPageAuthFlow", "AccountsPageModel.addAccountViaLogin coordinator returned \(imported.accountID)")
            let accounts = try await coordinator.listAccounts()
            authFlowLogger.log("AccountsPageModel.addAccountViaLogin listed \(accounts.count) accounts")
            AuthFlowDebugLog.write("AccountsPageAuthFlow", "AccountsPageModel.addAccountViaLogin listed \(accounts.count) accounts")
            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts, preferredSourceAccountID: imported.id)
            authFlowLogger.log("AccountsPageModel.addAccountViaLogin refreshed pending workspaces")
            AuthFlowDebugLog.write("AccountsPageAuthFlow", "AccountsPageModel.addAccountViaLogin refreshed pending workspaces")
            publishAndSyncLocalAccountsMutation(accounts)
            authFlowLogger.log("AccountsPageModel.addAccountViaLogin published local mutation")
            AuthFlowDebugLog.write("AccountsPageAuthFlow", "AccountsPageModel.addAccountViaLogin published local mutation")
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.imported_new_format", imported.label))
        } catch {
            authFlowLogger.error("AccountsPageModel.addAccountViaLogin failed: \(error.localizedDescription, privacy: .public)")
            AuthFlowDebugLog.write("AccountsPageAuthFlow", "AccountsPageModel.addAccountViaLogin failed: \(error.localizedDescription)")
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importAuthDocument(from url: URL, setAsCurrent: Bool) async {
        if setAsCurrent {
            isImporting = true
        } else {
            isAdding = true
        }
        defer {
            if setAsCurrent {
                isImporting = false
            } else {
                isAdding = false
            }
        }

        do {
            let imported = try await coordinator.importAccountFile(
                from: url,
                customLabel: nil,
                setAsCurrent: setAsCurrent
            )
            if setAsCurrent {
                syncCurrentAccountSelectionInBackground(accountID: imported.accountID)
            }
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts, preferredSourceAccountID: imported.id)
            publishAndSyncLocalAccountsMutation(accounts)
            let key = setAsCurrent
                ? "accounts.notice.imported_format"
                : "accounts.notice.imported_new_format"
            notice = NoticeMessage(style: .success, text: L10n.tr(key, imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteAccount(id: String) async {
        do {
            try await coordinator.deleteAccount(id: id)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts)
            publishAndSyncLocalAccountsMutation(accounts)
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
            await refreshPendingWorkspaceAuthorizations(from: accounts)
            publishAndSyncLocalAccountsMutation(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.team_name_updated"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
