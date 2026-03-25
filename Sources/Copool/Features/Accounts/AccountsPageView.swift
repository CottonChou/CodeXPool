import SwiftUI

struct AccountsPageView: View {
    @State private var areCardsPresented = false
    @State private var didRunInitialCardEntrance = false
    @StateObject private var store: AccountsPageViewStore

    let model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void

    init(
        model: AccountsPageModel,
        currentLocale: AppLocale,
        onSelectLocale: @escaping (AppLocale) -> Void
    ) {
        self.model = model
        self.currentLocale = currentLocale
        self.onSelectLocale = onSelectLocale
        _store = StateObject(wrappedValue: AccountsPageViewStore(model: model))
        let hasResolvedInitialState = model.hasResolvedInitialState
        _areCardsPresented = State(initialValue: hasResolvedInitialState)
        _didRunInitialCardEntrance = State(initialValue: hasResolvedInitialState)
    }

    var body: some View {
        AccountsPageShell(
            store: store,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            areCardsPresented: areCardsPresented,
            onTriggerAction: triggerAction,
            onToggleCollapse: toggleCollapse,
            onSwitchAccount: switchAccount,
            onRefreshAccountUsage: refreshUsage,
            onAuthorizeWorkspace: authorizeWorkspace,
            onDeletePendingWorkspace: deletePendingWorkspace,
            onDeleteAccount: deleteAccount
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            triggerInitialCardEntranceIfNeeded(for: contentAccountCount)
        }
        .onChange(of: contentAccountCount) { _, newValue in
            triggerInitialCardEntranceIfNeeded(for: newValue)
        }
    }

    private var contentAccountCount: Int? {
        guard case .content(let cards) = store.contentPresentation.state else { return nil }
        return cards.count
    }

    private func triggerInitialCardEntranceIfNeeded(for count: Int?) {
        guard count != nil, !didRunInitialCardEntrance else { return }
        didRunInitialCardEntrance = true
        areCardsPresented = true
    }

    private func triggerAction(_ intent: AccountsPageActionIntent) {
        Task { await model.handlePageAction(intent) }
    }

    private func toggleCollapse() {
        withAnimation(AccountsAnimationRules.collapseToggle) {
            model.toggleAllAccountsCollapsed()
            store.syncFromModel()
        }
    }

    private func switchAccount(id: String) {
        Task { await model.switchAccount(id: id) }
    }

    private func refreshUsage(forAccountID id: String) {
        Task { await model.refreshUsage(forAccountID: id) }
    }

    private func deleteAccount(id: String) {
        Task { await model.deleteAccount(id: id) }
    }

    private func authorizeWorkspace(id: String) {
        Task { await model.authorizePendingWorkspace(id: id) }
    }

    private func deletePendingWorkspace(id: String) {
        Task { await model.deletePendingWorkspace(id: id) }
    }
}
