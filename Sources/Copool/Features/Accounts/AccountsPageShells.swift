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
                    AccountsPageContentSection(
                        model: model,
                        areCardsPresented: areCardsPresented
                    )
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
                    AccountsPageContentSection(
                        model: model,
                        areCardsPresented: areCardsPresented
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
