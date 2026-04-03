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
    let presentation: AccountCardPresentation
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

    static func == (lhs: AccountCardViewState, rhs: AccountCardViewState) -> Bool {
        lhs.isCollapsed == rhs.isCollapsed
            && lhs.switching == rhs.switching
            && lhs.refreshing == rhs.refreshing
            && lhs.showsRefreshButton == rhs.showsRefreshButton
            && lhs.isRefreshEnabled == rhs.isRefreshEnabled
            && lhs.isUsageRefreshActive == rhs.isUsageRefreshActive
            && lhs.usageProgressDisplayMode == rhs.usageProgressDisplayMode
            && lhs.account.id == rhs.account.id
            && lhs.account.label == rhs.account.label
            && lhs.account.email == rhs.account.email
            && lhs.account.accountID == rhs.account.accountID
            && lhs.account.planType == rhs.account.planType
            && lhs.account.teamName == rhs.account.teamName
            && lhs.account.teamAlias == rhs.account.teamAlias
            && lhs.account.usage == rhs.account.usage
            && lhs.account.usageError == rhs.account.usageError
            && lhs.account.workspaceStatus == rhs.account.workspaceStatus
            && lhs.account.isCurrent == rhs.account.isCurrent
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
    func makeAccountCardViewState(
        for account: AccountSummary,
        locale: Locale = .autoupdatingCurrent
    ) -> AccountCardViewState {
        let isCollapsed = isAccountCollapsed(account.id)
        return AccountCardViewState(
            account: account,
            presentation: AccountCardPresentation(
                account: account,
                isCollapsed: isCollapsed,
                locale: locale,
                usageProgressDisplayMode: usageProgressDisplayMode
            ),
            isCollapsed: isCollapsed,
            switching: switchingAccountID == account.id,
            refreshing: isAccountRefreshing(account.id),
            showsRefreshButton: runtimePlatform == .macOS,
            isRefreshEnabled: canRefreshAccount(account.id),
            isUsageRefreshActive: isUsageRefreshActive(forAccountID: account.id),
            usageProgressDisplayMode: usageProgressDisplayMode
        )
    }

    func makeAccountCardViewState(
        forAccountID accountID: String,
        locale: Locale = .autoupdatingCurrent
    ) -> AccountCardViewState? {
        guard case .content(let accounts) = state else { return nil }
        guard let account = accounts.first(where: { $0.id == accountID && !$0.isWorkspaceDeactivated }) else {
            return nil
        }
        return makeAccountCardViewState(for: account, locale: locale)
    }

    func makeAccountCardViewStates(locale: Locale = .autoupdatingCurrent) -> [AccountCardViewState] {
        guard case .content(let accounts) = state else { return [] }
        return accounts
            .filter { !$0.isWorkspaceDeactivated }
            .map { makeAccountCardViewState(for: $0, locale: locale) }
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
