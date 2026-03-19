import SwiftUI

struct AccountsActionBarView: View {
    @ObservedObject var model: AccountsPageModel

    var body: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ScrollView(.horizontal) {
                HStack(spacing: LayoutRules.listRowSpacing) {
                    Button {
                        Task { await model.importCurrentAuth() }
                    } label: {
                        Label(
                            model.isImporting
                                ? L10n.tr("accounts.action.importing")
                                : L10n.tr("accounts.action.import_current_auth"),
                            systemImage: "square.and.arrow.down"
                        )
                        .lineLimit(1)
                    }
                    .disabled(!model.canImportCurrentAuthAction)
                    .copoolActionButtonStyle(prominent: true, density: .compact)

                    Button {
                        Task { await model.addAccountViaLogin() }
                    } label: {
                        Label(
                            model.isAdding
                                ? L10n.tr("accounts.action.waiting_for_login")
                                : L10n.tr("accounts.action.add_account"),
                            systemImage: "plus"
                        )
                        .lineLimit(1)
                    }
                    .disabled(!model.canAddAccountAction)
                    .copoolActionButtonStyle(prominent: true, density: .compact)

                    Button {
                        Task { await model.smartSwitch() }
                    } label: {
                        Label("accounts.action.smart_switch", systemImage: "wand.and.stars")
                            .lineLimit(1)
                    }
                    .copoolActionButtonStyle(prominent: true, density: .compact)
                    .disabled(!model.canSmartSwitchAction)

                    Button {
                        Task { await model.refreshUsage() }
                    } label: {
                        ToolbarIconLabel(
                            systemImage: "arrow.trianglehead.clockwise.rotate.90",
                            isSpinning: model.isRefreshSpinnerActive,
                            opticalScale: LayoutRules.toolbarRefreshIconOpticalScale
                        )
                    }
                    .disabled(!model.canRefreshUsageAction)
                    .copoolActionButtonStyle(prominent: true, tint: .mint, density: .compact)
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)

            CollapseChevronButton(isExpanded: !model.areAllAccountsCollapsed) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.toggleAllAccountsCollapsed()
                }
            }
            .accessibilityLabel(
                Text(
                    model.areAllAccountsCollapsed
                        ? L10n.tr("accounts.action.expand_all")
                        : L10n.tr("accounts.action.collapse_all")
                )
            )
        }
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

        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await model.addAccountViaLogin() }
            } label: {
                ToolbarIconLabel(systemImage: "plus")
            }
            .disabled(!model.canAddAccountAction)
            .accessibilityLabel(
                Text(
                    model.isAdding
                        ? L10n.tr("accounts.action.waiting_for_login")
                        : L10n.tr("accounts.action.add_account")
                )
            )
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await model.refreshUsage() }
            } label: {
                ToolbarIconLabel(
                    systemImage: "arrow.trianglehead.clockwise.rotate.90",
                    isSpinning: model.isRefreshSpinnerActive,
                    opticalScale: LayoutRules.toolbarRefreshIconOpticalScale
                )
            }
            .disabled(!model.canRefreshUsageAction)
            .accessibilityLabel(Text("common.refresh_usage"))
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.toggleAllAccountsCollapsed()
                }
            } label: {
                ToolbarIconLabel(
                    systemImage: model.areAllAccountsCollapsed ? "chevron.down" : "chevron.up"
                )
            }
            .accessibilityLabel(
                Text(
                    model.areAllAccountsCollapsed
                        ? L10n.tr("accounts.action.expand_all")
                        : L10n.tr("accounts.action.collapse_all")
                )
            )
        }
    }
}
#endif
