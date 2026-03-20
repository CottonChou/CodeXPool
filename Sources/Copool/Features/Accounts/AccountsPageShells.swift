import SwiftUI

struct AccountsPageShell: View {
    let model: AccountsPageModel
    let macActionBarPresentation: AccountsActionBarPresentation
    let leadingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let trailingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        #if os(iOS)
        AccountsIOSPageShell(
            model: model,
            leadingToolbarButtons: leadingToolbarButtons,
            trailingToolbarButtons: trailingToolbarButtons,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            areCardsPresented: areCardsPresented,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse,
            onSwitchAccount: onSwitchAccount,
            onRefreshAccountUsage: onRefreshAccountUsage,
            onDeleteAccount: onDeleteAccount
        )
        #else
        AccountsMacPageShell(
            model: model,
            actionBarPresentation: macActionBarPresentation,
            areCardsPresented: areCardsPresented,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse,
            onSwitchAccount: onSwitchAccount,
            onRefreshAccountUsage: onRefreshAccountUsage,
            onDeleteAccount: onDeleteAccount
        )
        #endif
    }
}

#if os(iOS)
private struct AccountsIOSPageShell: View {
    let model: AccountsPageModel
    let leadingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let trailingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountsPageContentSection(
                        model: model,
                        areCardsPresented: areCardsPresented,
                        onSwitchAccount: onSwitchAccount,
                        onRefreshAccountUsage: onRefreshAccountUsage,
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
                AccountsToolbarActions(
                    leadingButtons: leadingToolbarButtons,
                    trailingButtons: trailingToolbarButtons,
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
    let model: AccountsPageModel
    let actionBarPresentation: AccountsActionBarPresentation
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
            AccountsActionBarView(
                presentation: actionBarPresentation,
                onTriggerAction: onTriggerAction,
                onToggleCollapse: onToggleCollapse
            )
                .padding(.horizontal, LayoutRules.pagePadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountsPageContentSection(
                        model: model,
                        areCardsPresented: areCardsPresented,
                        onSwitchAccount: onSwitchAccount,
                        onRefreshAccountUsage: onRefreshAccountUsage,
                        onDeleteAccount: onDeleteAccount
                    )
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, LayoutRules.pagePadding)
    }
}
