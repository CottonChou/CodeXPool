import SwiftUI

struct AccountCardView: View {
    let account: AccountSummary
    let isCollapsed: Bool
    let switching: Bool
    let refreshing: Bool
    let isRefreshEnabled: Bool
    let isUsageRefreshActive: Bool
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    @Environment(\.locale) private var locale
    @State private var isHoveringCollapsedSwitch = false
    @State private var isCollapsedSwitchOverlayPresented = false
    @State private var displayedCollapsed: Bool
    @State private var contentSwapTask: Task<Void, Never>?

    init(
        account: AccountSummary,
        isCollapsed: Bool,
        switching: Bool,
        refreshing: Bool,
        isRefreshEnabled: Bool,
        isUsageRefreshActive: Bool,
        onSwitch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.account = account
        self.isCollapsed = isCollapsed
        self.switching = switching
        self.refreshing = refreshing
        self.isRefreshEnabled = isRefreshEnabled
        self.isUsageRefreshActive = isUsageRefreshActive
        self.onSwitch = onSwitch
        self.onRefresh = onRefresh
        self.onDelete = onDelete
        _displayedCollapsed = State(initialValue: isCollapsed)
    }

    private var presentation: AccountCardPresentation {
        AccountCardPresentation(account: account, isCollapsed: displayedCollapsed, locale: locale)
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
        VStack(alignment: .leading, spacing: 8) {
            AccountCardHeaderSection(
                presentation: presentation,
                isCollapsed: displayedCollapsed,
                isCurrent: account.isCurrent,
                palette: palette,
                onDelete: onDelete
            )

            Text(presentation.displayAccountName)
                .font(.headline)
                .foregroundStyle(account.isCurrent ? palette.toneColor : .primary)
                .lineLimit(displayedCollapsed ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)

            if displayedCollapsed {
                AccountCardCompactUsageSection(presentation: presentation)
            } else {
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
                isCollapsed: displayedCollapsed,
                isCurrent: account.isCurrent,
                switching: switching,
                refreshing: refreshing,
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
        .onHover { hovering in
            guard interactionPresentation.canHoverSwitchOverlay else {
                isHoveringCollapsedSwitch = false
                return
            }
            guard isHoveringCollapsedSwitch != hovering else { return }
            withAnimation(AccountsAnimationRules.cardHoverOverlay) {
                isHoveringCollapsedSwitch = hovering
            }
        }
        #if os(iOS)
        .onLongPressGesture(minimumDuration: AccountsAnimationRules.collapsedOverlayMinimumPressDuration) {
            guard interactionPresentation.canRevealCollapsedSwitchOverlay else { return }
            withAnimation(AccountsAnimationRules.cardHoverOverlay) {
                isCollapsedSwitchOverlayPresented = true
            }
        }
        #endif
        .onChange(of: isCollapsed) { _, collapsed in
            syncDisplayedCollapsed(with: collapsed)
            if !collapsed {
                dismissCollapsedSwitchOverlay()
            }
        }
        .onChange(of: account.isCurrent) { _, isCurrent in
            if isCurrent {
                dismissCollapsedSwitchOverlay()
            }
        }
        .onDisappear {
            contentSwapTask?.cancel()
            contentSwapTask = nil
        }
    }

    private func dismissCollapsedSwitchOverlay() {
        guard isCollapsedSwitchOverlayPresented else { return }
        withAnimation(AccountsAnimationRules.cardHoverOverlay) {
            isCollapsedSwitchOverlayPresented = false
        }
    }

    private func syncDisplayedCollapsed(with targetCollapsed: Bool) {
        contentSwapTask?.cancel()

        guard displayedCollapsed != targetCollapsed else {
            contentSwapTask = nil
            return
        }

        contentSwapTask = Task { @MainActor in
            try? await Task.sleep(for: AccountCardMorphRules.contentSwapDelay)
            guard !Task.isCancelled else { return }
            withAnimation(AccountCardMorphRules.contentAnimation) {
                displayedCollapsed = targetCollapsed
            }
            contentSwapTask = nil
        }
    }
}
