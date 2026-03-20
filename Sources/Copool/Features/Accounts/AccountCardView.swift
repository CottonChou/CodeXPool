import SwiftUI

struct AccountCardView: View {
    let account: AccountSummary
    let isCollapsed: Bool
    let switching: Bool
    let onSwitch: () -> Void
    let onDelete: () -> Void

    @Environment(\.locale) private var locale
    @State private var isHoveringCollapsedSwitch = false
    @State private var isCollapsedSwitchOverlayPresented = false

    private var presentation: AccountCardPresentation {
        AccountCardPresentation(account: account, isCollapsed: isCollapsed, locale: locale)
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
                isCollapsed: isCollapsed,
                isCurrent: account.isCurrent,
                palette: palette,
                onDelete: onDelete
            )

            Text(presentation.displayAccountName)
                .font(.headline)
                .foregroundStyle(account.isCurrent ? palette.toneColor : .primary)
                .lineLimit(isCollapsed ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)

            if isCollapsed {
                AccountCardCompactUsageSection(presentation: presentation)
            } else {
                AccountCardExpandedUsageSection(
                    presentation: presentation,
                    usageError: account.usageError
                )
            }
        }
        .padding(isCollapsed ? 8 : 10)
        .cardSurface(cornerRadius: 12, tint: palette.surfaceTint)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(account.isCurrent ? palette.toneColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            AccountExpandedTrailingOverlay(
                isCollapsed: isCollapsed,
                isCurrent: account.isCurrent,
                switching: switching,
                palette: palette,
                onSwitch: onSwitch
            )
        }
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
            withAnimation(.easeInOut(duration: 0.16)) {
                isHoveringCollapsedSwitch = hovering
            }
        }
        #if os(iOS)
        .onLongPressGesture(minimumDuration: 0.35) {
            guard interactionPresentation.canRevealCollapsedSwitchOverlay else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
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

    private func dismissCollapsedSwitchOverlay() {
        guard isCollapsedSwitchOverlayPresented else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isCollapsedSwitchOverlayPresented = false
        }
    }
}
