import SwiftUI

struct AccountsPageShell: View {
    @ObservedObject var contentStore: AccountsPageViewStore
    @ObservedObject var chromeStore: AccountsPageChromeStore
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        #if os(iOS)
        AccountsIOSPageShell(
            contentStore: contentStore,
            chromeStore: chromeStore,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            areCardsPresented: areCardsPresented,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse,
            onSwitchAccount: onSwitchAccount,
            onRefreshAccountUsage: onRefreshAccountUsage,
            onAuthorizeWorkspace: onAuthorizeWorkspace,
            onDeletePendingWorkspace: onDeletePendingWorkspace,
            onDeleteAccount: onDeleteAccount
        )
        #else
        AccountsMacPageShell(
            contentStore: contentStore,
            chromeStore: chromeStore,
            areCardsPresented: areCardsPresented,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse,
            onSwitchAccount: onSwitchAccount,
            onRefreshAccountUsage: onRefreshAccountUsage,
            onAuthorizeWorkspace: onAuthorizeWorkspace,
            onDeletePendingWorkspace: onDeletePendingWorkspace,
            onDeleteAccount: onDeleteAccount
        )
        #endif
    }
}

#if os(iOS)
private struct AccountsIOSPageShell: View {
    @ObservedObject var contentStore: AccountsPageViewStore
    @ObservedObject var chromeStore: AccountsPageChromeStore
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountsPageContentSection(
                        presentation: contentStore.contentPresentation,
                        cardStoreProvider: contentStore.cardStore(for:),
                        availableViewportSize: proxy.size,
                        areCardsPresented: areCardsPresented,
                        onSwitchAccount: onSwitchAccount,
                        onRefreshAccountUsage: onRefreshAccountUsage,
                        onAuthorizeWorkspace: onAuthorizeWorkspace,
                        onDeletePendingWorkspace: onDeletePendingWorkspace,
                        onDeleteAccount: onDeleteAccount
                    )
                }
                .padding(.top, LayoutRules.iOSAccountsContentTopPadding(safeAreaTop: proxy.safeAreaInsets.top))
                .padding(.bottom, LayoutRules.iOSAccountsContentBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: [.top, .bottom])
            .refreshable {
                onTriggerAction(.refreshUsage)
            }
            .toolbar {
                AccountsToolbarContent(
                    leadingButtons: chromeStore.leadingToolbarButtons,
                    trailingButtons: chromeStore.trailingToolbarButtons,
                    currentLocale: currentLocale,
                    onSelectLocale: onSelectLocale,
                    onTriggerAction: onTriggerAction,
                    onToggleCollapse: onToggleCollapse
                )
            }
        }
    }
}
#endif

private struct AccountsMacPageShell: View {
    @ObservedObject var contentStore: AccountsPageViewStore
    @ObservedObject var chromeStore: AccountsPageChromeStore
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    private var pageContentWidth: CGFloat {
        LayoutRules.accountsPageContentWidth(isCompactWidth: false) ?? LayoutRules.accountsPageTargetWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
            AccountsActionBarContainer(
                presentation: chromeStore.macActionBarPresentation,
                onTriggerAction: onTriggerAction,
                onToggleCollapse: onToggleCollapse
            )
            .padding(.horizontal, LayoutRules.pagePadding)
            .frame(width: pageContentWidth, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountsPageContentSection(
                        presentation: contentStore.contentPresentation,
                        cardStoreProvider: contentStore.cardStore(for:),
                        availableViewportSize: CGSize(
                            width: pageContentWidth,
                            height: LayoutRules.defaultPanelHeight
                        ),
                        areCardsPresented: areCardsPresented,
                        onSwitchAccount: onSwitchAccount,
                        onRefreshAccountUsage: onRefreshAccountUsage,
                        onAuthorizeWorkspace: onAuthorizeWorkspace,
                        onDeletePendingWorkspace: onDeletePendingWorkspace,
                        onDeleteAccount: onDeleteAccount
                    )
                }
                .padding(.bottom, 12)
                .frame(width: pageContentWidth, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: pageContentWidth, alignment: .topLeading)
        .padding(.top, LayoutRules.pagePadding)
    }
}

private struct AccountsActionBarContainer: View {
    let presentation: AccountsActionBarPresentation
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        AccountsActionBarView(
            presentation: presentation,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse
        )
    }
}

#if os(iOS)
private struct AccountsToolbarContent: ToolbarContent {
    let leadingButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let trailingButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void

    var body: some ToolbarContent {
        AccountsToolbarActions(
            leadingButtons: leadingButtons,
            trailingButtons: trailingButtons,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse
        )
    }
}
#endif
