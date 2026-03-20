import SwiftUI

struct AccountsActionBarView: View {
    @ObservedObject var model: AccountsPageModel

    var body: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ScrollView(.horizontal) {
                AccountsActionStrip(
                    descriptors: model.desktopActionButtons,
                    onTrigger: triggerAction
                )
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)

            CollapseChevronButton(isExpanded: model.collapsePresentation.isExpanded) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.toggleAllAccountsCollapsed()
                }
            }
            .accessibilityLabel(Text(model.collapsePresentation.accessibilityLabel))
        }
    }

    private func triggerAction(_ intent: AccountsPageActionIntent) {
        Task { await model.handlePageAction(intent) }
    }
}

#if os(iOS)
struct AccountsToolbarActions: ToolbarContent {
    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            LanguageMenuButton(
                currentLocale: currentLocale,
                onSelectLocale: onSelectLocale
            ) {
                ToolbarIconLabel(systemImage: "globe")
            }
        }

        ToolbarItemGroup(placement: .topBarLeading) {
            AccountsToolbarButtonGroup(
                descriptors: model.leadingToolbarButtons,
                onTrigger: triggerAction
            )
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            AccountsToolbarButtonGroup(
                descriptors: model.trailingToolbarButtons,
                onTrigger: triggerAction
            )
        }
    }

    private func triggerAction(_ intent: AccountsPageActionIntent) {
        if intent == .toggleCollapse {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.toggleAllAccountsCollapsed()
            }
            return
        }
        Task { await model.handlePageAction(intent) }
    }
}
#endif
