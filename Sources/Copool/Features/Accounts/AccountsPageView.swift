import SwiftUI

struct AccountsPageView: View {
    @State private var areCardsPresented = false
    @State private var didRunInitialCardEntrance = false

    @ObservedObject var model: AccountsPageModel
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
        let hasResolvedInitialState = model.hasResolvedInitialState
        _areCardsPresented = State(initialValue: hasResolvedInitialState)
        _didRunInitialCardEntrance = State(initialValue: hasResolvedInitialState)
    }

    var body: some View {
        platformLayout
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.loadIfNeeded()
        }
        .onAppear {
            triggerInitialCardEntranceIfNeeded(for: contentAccountCount)
        }
        .onChange(of: contentAccountCount) { _, newValue in
            triggerInitialCardEntranceIfNeeded(for: newValue)
        }
    }

    @ViewBuilder
    private var platformLayout: some View {
        #if os(iOS)
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contentView
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
        #else
        VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
            AccountsActionBarView(model: model)
                .padding(.horizontal, LayoutRules.pagePadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contentView
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, LayoutRules.pagePadding)
        #endif
    }

    @ViewBuilder
    private var contentView: some View {
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
            let isOverviewMode = model.areAllAccountsCollapsed
            let columns = accountGridColumns(isOverviewMode: isOverviewMode)
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

    private var contentAccountCount: Int? {
        guard case .content(let accounts) = model.state else { return nil }
        return accounts.count
    }

    private func triggerInitialCardEntranceIfNeeded(for count: Int?) {
        guard count != nil, !didRunInitialCardEntrance else { return }
        didRunInitialCardEntrance = true
        areCardsPresented = true
    }

    private func accountGridColumns(isOverviewMode: Bool) -> [GridItem] {
        #if os(iOS)
        LayoutRules.accountsGridColumns(isOverviewMode: isOverviewMode, isCompactWidth: true)
        #else
        LayoutRules.accountsGridColumns(isOverviewMode: isOverviewMode, isCompactWidth: false)
        #endif
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
