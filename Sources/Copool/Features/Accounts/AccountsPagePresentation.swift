import Foundation

struct AccountsPageContentPresentation: Equatable {
    let state: ViewState<[String]>
    let pendingWorkspaceCards: [PendingWorkspaceAuthorizationCardViewState]
    let pendingWorkspaceError: String?
    let isOverviewMode: Bool

    var shouldShowPendingWorkspaceSection: Bool {
        !pendingWorkspaceCards.isEmpty || pendingWorkspaceError != nil
    }
}

struct AccountsActionBarPresentation: Equatable {
    let descriptors: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let collapse: AccountsCollapsePresentation
}

struct AccountCardViewState: Equatable, Identifiable {
    let account: AccountSummary
    let isCollapsed: Bool
    let switching: Bool
    let refreshing: Bool
    let showsRefreshButton: Bool
    let isRefreshEnabled: Bool
    let isUsageRefreshActive: Bool
    let usageProgressDisplayMode: UsageProgressDisplayMode

    var id: String {
        account.id
    }
}

struct PendingWorkspaceAuthorizationCardViewState: Equatable, Identifiable {
    enum DeletionMode: Equatable {
        case dismissCandidate
        case deleteAccount
    }

    let id: String
    let workspaceID: String
    let workspaceName: String
    let email: String?
    let planType: String?
    let status: WorkspaceAuthorizationCandidateStatus
    let authorizing: Bool
    let deletionMode: DeletionMode
}

extension AccountsPageModel {
    func makeAccountCardViewStates() -> [AccountCardViewState] {
        guard case .content(let accounts) = state else { return [] }
        return accounts.filter { !$0.isWorkspaceDeactivated }.map { account in
            AccountCardViewState(
                account: account,
                isCollapsed: isAccountCollapsed(account.id),
                switching: switchingAccountID == account.id,
                refreshing: isAccountRefreshing(account.id),
                showsRefreshButton: runtimePlatform == .macOS,
                isRefreshEnabled: canRefreshAccount(account.id),
                isUsageRefreshActive: isUsageRefreshActive(forAccountID: account.id),
                usageProgressDisplayMode: usageProgressDisplayMode
            )
        }
    }

    func makeContentPresentation() -> AccountsPageContentPresentation {
        let contentState = state.mapContent { accounts in
            accounts
                .filter { !$0.isWorkspaceDeactivated }
                .map(\.id)
        }
        let deactivatedAccountCards = currentDeactivatedAccountPendingCards()
        let pendingAuthorizationCards = pendingWorkspaceAuthorizations.map { candidate in
            PendingWorkspaceAuthorizationCardViewState(
                id: candidate.id,
                workspaceID: candidate.workspaceID,
                workspaceName: candidate.workspaceName,
                email: candidate.email,
                planType: candidate.planType,
                status: candidate.status,
                authorizing: authorizingWorkspaceID == candidate.id,
                deletionMode: .dismissCandidate
            )
        }
        let pendingCards = (deactivatedAccountCards + pendingAuthorizationCards).sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .deactivated
            }
            return lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
        }
        let pendingError = pendingCards.isEmpty ? nil : pendingWorkspaceAuthorizationError
        return AccountsPageContentPresentation(
            state: contentState,
            pendingWorkspaceCards: pendingCards,
            pendingWorkspaceError: pendingError,
            isOverviewMode: areAllAccountsCollapsed
        )
    }

    func makeMacActionBarPresentation() -> AccountsActionBarPresentation {
        AccountsActionBarPresentation(
            descriptors: desktopActionButtons,
            collapse: collapsePresentation
        )
    }

    private func currentDeactivatedAccountPendingCards() -> [PendingWorkspaceAuthorizationCardViewState] {
        guard case .content(let accounts) = state else { return [] }
        return accounts.compactMap { account in
            guard account.isWorkspaceDeactivated else { return nil }
            return PendingWorkspaceAuthorizationCardViewState(
                id: account.id,
                workspaceID: account.accountID,
                workspaceName: account.displayTeamName ?? account.teamName ?? account.label,
                email: account.email,
                planType: account.planType ?? account.usage?.planType,
                status: .deactivated,
                authorizing: false,
                deletionMode: .deleteAccount
            )
        }
    }
}

private extension ViewState {
    func mapContent<NewValue>(_ transform: (Value) -> NewValue) -> ViewState<NewValue> {
        switch self {
        case .loading:
            return .loading
        case .empty(let message):
            return .empty(message: message)
        case .content(let value):
            return .content(transform(value))
        case .error(let message):
            return .error(message: message)
        }
    }
}
