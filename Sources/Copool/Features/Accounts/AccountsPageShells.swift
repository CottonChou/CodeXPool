import SwiftUI

struct AccountsPageShell: View {
    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool

    var body: some View {
        #if os(iOS)
        AccountsIOSPageShell(
            model: model,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            areCardsPresented: areCardsPresented
        )
        #else
        AccountsMacPageShell(model: model, areCardsPresented: areCardsPresented)
        #endif
    }
}

#if os(iOS)
private struct AccountsIOSPageShell: View {
    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountsPageContent(model: model, areCardsPresented: areCardsPresented)
                }
                .padding(.top, LayoutRules.iOSAccountsContentTopPadding(safeAreaTop: proxy.safeAreaInsets.top))
                .padding(.bottom, LayoutRules.iOSAccountsContentBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: [.top, .bottom])
            .refreshable {
                await model.refreshUsage()
            }
            .toolbar {
                AccountsToolbarActions(
                    model: model,
                    currentLocale: currentLocale,
                    onSelectLocale: onSelectLocale
                )
            }
        }
    }
}
#endif

private struct AccountsMacPageShell: View {
    @ObservedObject var model: AccountsPageModel
    let areCardsPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
            AccountsActionBarView(model: model)
                .padding(.horizontal, LayoutRules.pagePadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountsPageContent(model: model, areCardsPresented: areCardsPresented)
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, LayoutRules.pagePadding)
    }
}

private struct AccountsPageContent: View {
    @ObservedObject var model: AccountsPageModel
    let areCardsPresented: Bool

    var body: some View {
        switch model.state {
        case .loading:
            ProgressView(L10n.tr("accounts.loading.message"))
                .frame(maxWidth: .infinity, minHeight: 180)
        case .empty(let message):
            EmptyStateView(title: L10n.tr("accounts.empty.title"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .error(let message):
            EmptyStateView(title: L10n.tr("accounts.error.load_failed"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .content(let accounts):
            AccountsGridSection(
                accounts: accounts,
                model: model,
                areCardsPresented: areCardsPresented
            )
        }
    }
}

private struct AccountsGridSection: View {
    let accounts: [AccountSummary]
    @ObservedObject var model: AccountsPageModel
    let areCardsPresented: Bool

    private var isOverviewMode: Bool {
        model.areAllAccountsCollapsed
    }

    private var columns: [GridItem] {
        #if os(iOS)
        LayoutRules.accountsGridColumns(isOverviewMode: isOverviewMode, isCompactWidth: true)
        #else
        LayoutRules.accountsGridColumns(isOverviewMode: isOverviewMode, isCompactWidth: false)
        #endif
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: LayoutRules.accountsRowSpacing
        ) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                AccountCardView(
                    account: account,
                    isCollapsed: model.isAccountCollapsed(account.id),
                    switching: model.switchingAccountID == account.id,
                    onSwitch: { Task { await model.switchAccount(id: account.id) } },
                    onDelete: { Task { await model.deleteAccount(id: account.id) } }
                )
                .copoolCardEntrance(index: index, isPresented: areCardsPresented)
                .modifier(AccountCardFrameModifier(isOverviewMode: isOverviewMode))
            }
        }
        .animation(
            .spring(response: 0.36, dampingFraction: 0.84),
            value: accounts.map(\.id)
        )
        .padding(.horizontal, LayoutRules.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CardEntranceModifier: ViewModifier {
    let index: Int
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 22)
            .scaleEffect(isPresented ? 1 : 0.985)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.86)
                    .delay(min(0.28, Double(index) * 0.035)),
                value: isPresented
            )
    }
}

private extension View {
    func copoolCardEntrance(index: Int, isPresented: Bool) -> some View {
        modifier(CardEntranceModifier(index: index, isPresented: isPresented))
    }
}

private struct AccountCardFrameModifier: ViewModifier {
    let isOverviewMode: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(maxWidth: .infinity, alignment: .topLeading)
        #else
        content.frame(
            width: LayoutRules.accountsCardFrameWidth(isOverviewMode: isOverviewMode, isCompactWidth: false),
            alignment: .topLeading
        )
        #endif
    }
}
