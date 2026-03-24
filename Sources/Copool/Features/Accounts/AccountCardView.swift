import SwiftUI

struct AccountCardView: View {
    let account: AccountSummary
    let isCollapsed: Bool
    let switching: Bool
    let refreshing: Bool
    let showsRefreshButton: Bool
    let isRefreshEnabled: Bool
    let isUsageRefreshActive: Bool
    let usageProgressDisplayMode: UsageProgressDisplayMode
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    @Environment(\.locale) private var locale
    @State private var isHoveringCollapsedSwitch = false
    @State private var isCollapsedSwitchOverlayPresented = false

    init(
        account: AccountSummary,
        isCollapsed: Bool,
        switching: Bool,
        refreshing: Bool,
        showsRefreshButton: Bool,
        isRefreshEnabled: Bool,
        isUsageRefreshActive: Bool,
        usageProgressDisplayMode: UsageProgressDisplayMode,
        onSwitch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.account = account
        self.isCollapsed = isCollapsed
        self.switching = switching
        self.refreshing = refreshing
        self.showsRefreshButton = showsRefreshButton
        self.isRefreshEnabled = isRefreshEnabled
        self.isUsageRefreshActive = isUsageRefreshActive
        self.usageProgressDisplayMode = usageProgressDisplayMode
        self.onSwitch = onSwitch
        self.onRefresh = onRefresh
        self.onDelete = onDelete
    }

    private var presentation: AccountCardPresentation {
        AccountCardPresentation(
            account: account,
            isCollapsed: isCollapsed,
            locale: locale,
            usageProgressDisplayMode: usageProgressDisplayMode
        )
    }

    private var palette: AccountCardPalette {
        AccountCardPalette(accent: presentation.accent, isCurrent: account.isCurrent)
    }

    private var interactionPresentation: AccountCardInteractionPresentation {
        AccountCardInteractionPresentation(
            isCollapsed: isCollapsed,
            isCurrent: account.isCurrent,
            switching: switching,
            isHoveringCollapsedSwitch: isHoveringCollapsedSwitch,
            isCollapsedSwitchOverlayPresented: isCollapsedSwitchOverlayPresented,
            platform: accountCardInteractionPlatform
        )
    }

    private var accountCardInteractionPlatform: AccountCardInteractionPlatform {
        #if os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }

    var body: some View {
        cardBody
            .copoolCollapsedSwitchHover(
                enabled: interactionPresentation.canHoverSwitchOverlay,
                isHoveringCollapsedSwitch: $isHoveringCollapsedSwitch
            )
            #if os(iOS)
            .onLongPressGesture(minimumDuration: AccountsAnimationRules.collapsedOverlayMinimumPressDuration) {
                guard interactionPresentation.canRevealCollapsedSwitchOverlay else { return }
                withAnimation(AccountsAnimationRules.cardHoverOverlay) {
                    isCollapsedSwitchOverlayPresented = true
                }
            }
            #endif
            .onChange(of: isCollapsed) { _, collapsed in
                if !collapsed {
                    dismissCollapsedSwitchOverlay()
                }
            }
            .onChange(of: account.isCurrent) { _, isCurrent in
                if isCurrent {
                    dismissCollapsedSwitchOverlay()
                }
            }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCollapsed {
                AccountCompactHeaderContent(
                    planLabel: presentation.planLabel,
                    workspaceLabel: presentation.teamNameTag,
                    statusLabel: presentation.statusLabel,
                    accountName: presentation.displayAccountName,
                    accentColor: palette.toneColor,
                    titleFont: .headline,
                    titleColor: account.isCurrent ? palette.toneColor : .primary,
                    spacing: 8
                )
                AccountCardCompactUsageSection(presentation: presentation)
            } else {
                AccountCardHeaderSection(
                    presentation: presentation,
                    isCollapsed: isCollapsed,
                    isCurrent: account.isCurrent,
                    palette: palette,
                    onDelete: onDelete
                )

                Text(presentation.displayAccountName)
                    .font(.headline)
                    .foregroundStyle(account.isCurrent ? palette.toneColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                AccountCardExpandedUsageSection(presentation: presentation)
            }
        }
        .padding(isCollapsed ? 8 : 10)
        .accountCardSurface(cornerRadius: 12, tint: palette.surfaceTint)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(account.isCurrent ? palette.toneColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            AccountCardBottomOverlay(
                isCollapsed: isCollapsed,
                isCurrent: account.isCurrent,
                switching: switching,
                refreshing: refreshing,
                showsRefreshButton: showsRefreshButton,
                isRefreshEnabled: isRefreshEnabled,
                usageError: isUsageRefreshActive ? nil : account.usageError,
                palette: palette,
                onSwitch: onSwitch,
                onRefresh: onRefresh
            )
        }
        .animation(AccountCardMorphRules.animation, value: isCollapsed)
        .animation(AccountCardMorphRules.animation, value: account.isCurrent)
        .overlay {
            AccountCollapsedSwitchOverlay(
                isVisible: interactionPresentation.isCollapsedSwitchOverlayVisible,
                switching: switching,
                onDismiss: dismissCollapsedSwitchOverlay,
                onSwitch: onSwitch
            )
        }
    }

    private func dismissCollapsedSwitchOverlay() {
        guard isCollapsedSwitchOverlayPresented else { return }
        withAnimation(AccountsAnimationRules.cardHoverOverlay) {
            isCollapsedSwitchOverlayPresented = false
        }
    }
}

private struct CollapsedSwitchHoverModifier: ViewModifier {
    let enabled: Bool
    @Binding var isHoveringCollapsedSwitch: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onHover { hovering in
                guard isHoveringCollapsedSwitch != hovering else { return }
                withAnimation(AccountsAnimationRules.cardHoverOverlay) {
                    isHoveringCollapsedSwitch = hovering
                }
            }
        } else {
            content
                .onAppear {
                    isHoveringCollapsedSwitch = false
                }
        }
    }
}

private extension View {
    func copoolCollapsedSwitchHover(
        enabled: Bool,
        isHoveringCollapsedSwitch: Binding<Bool>
    ) -> some View {
        modifier(
            CollapsedSwitchHoverModifier(
                enabled: enabled,
                isHoveringCollapsedSwitch: isHoveringCollapsedSwitch
            )
        )
    }
}
