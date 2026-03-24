import Foundation

struct AccountsPageContentPresentation: Equatable {
    let state: ViewState<[String]>
    let pendingWorkspaceCards: [PendingWorkspaceAuthorizationCardViewState]
    let pendingWorkspaceError: String?
    let isOverviewMode: Bool
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
    let candidate: WorkspaceAuthorizationCandidate
    let authorizing: Bool

    var id: String {
        candidate.id
    }
}

extension AccountsPageModel {
    func makeAccountCardViewStates() -> [AccountCardViewState] {
        guard case .content(let accounts) = state else { return [] }
        return accounts.map { account in
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
            accounts.map(\.id)
        }
        return AccountsPageContentPresentation(
            state: contentState,
            pendingWorkspaceCards: pendingWorkspaceAuthorizations.map { candidate in
                PendingWorkspaceAuthorizationCardViewState(
                    candidate: candidate,
                    authorizing: authorizingWorkspaceID == candidate.id
                )
            },
            pendingWorkspaceError: pendingWorkspaceAuthorizationError,
            isOverviewMode: areAllAccountsCollapsed
        )
    }

    func makeMacActionBarPresentation() -> AccountsActionBarPresentation {
        AccountsActionBarPresentation(
            descriptors: desktopActionButtons,
            collapse: collapsePresentation
        )
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
