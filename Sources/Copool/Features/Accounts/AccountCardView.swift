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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            title

            if isCollapsed {
                compactUsageSection
            } else {
                expandedUsageSection
            }
        }
        .padding(isCollapsed ? 8 : 10)
        .cardSurface(cornerRadius: 12, tint: currentCardSurfaceTint)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(account.isCurrent ? toneColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            expandedTrailingOverlay
        }
        .overlay {
            collapsedSwitchOverlay
        }
        .onHover { hovering in
            guard canHoverSwitchOverlay else {
                isHoveringCollapsedSwitch = false
                return
            }
            withAnimation(.easeInOut(duration: 0.16)) {
                isHoveringCollapsedSwitch = hovering
            }
        }
        #if os(iOS)
        .onLongPressGesture(minimumDuration: 0.35) {
            guard canRevealCollapsedSwitchOverlay else { return }
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    stamp(text: presentation.planLabel, tint: toneColor.opacity(0.18), fg: toneColor)
                    if let teamNameTag = presentation.teamNameTag, !isCollapsed {
                        stamp(text: teamNameTag, tint: toneColor.opacity(0.18), fg: toneColor)
                    }
                }
            }

            Spacer(minLength: 0)

            if !isCollapsed {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .copoolActionButtonStyle(
                    prominent: true,
                    tint: .red,
                    density: .compact,
                    iOSStyle: .liquidGlass
                )
                .tint(.red)
            }
        }
    }

    private var title: some View {
        Text(presentation.displayAccountName)
            .font(.headline)
            .foregroundStyle(account.isCurrent ? toneColor : .primary)
            .lineLimit(isCollapsed ? 1 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .truncationMode(.tail)
    }

    private var compactUsageSection: some View {
        HStack(spacing: 14) {
            CompactUsageRing(
                usedPercent: presentation.compactUsage.fiveHourUsedPercent,
                tint: .orange
            )
            CompactUsageRing(
                usedPercent: presentation.compactUsage.oneWeekUsedPercent,
                tint: .teal
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var expandedUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            windowSection(presentation.fiveHourWindow, tint: .orange)
            windowSection(presentation.oneWeekWindow, tint: .teal)

            HStack(spacing: 8) {
                Text(L10n.tr("accounts.card.credits_format", presentation.creditsText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 64)
                Spacer(minLength: 0)
            }

            if let usageError = account.usageError, !usageError.isEmpty {
                Text(usageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var expandedTrailingOverlay: some View {
        if !isCollapsed {
            if account.isCurrent {
                stamp(
                    text: L10n.tr("accounts.card.current"),
                    tint: toneColor.opacity(0.24),
                    fg: toneColor
                )
                .padding(8)
            } else {
                switchButton
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var collapsedSwitchOverlay: some View {
        if collapsedSwitchOverlayVisible {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
                    .onTapGesture {
                        dismissCollapsedSwitchOverlay()
                    }

                switchButton(labelStyle: .expanded)
            }
            .transition(.opacity)
        }
    }

    private var switchButton: some View {
        switchButton(labelStyle: .iconOnly)
    }

    private func switchButton(labelStyle: SwitchButtonLabelStyle) -> some View {
        Button {
            onSwitch()
        } label: {
            if switching {
                ProgressView()
                    .controlSize(.small)
            } else {
                switch labelStyle {
                case .iconOnly:
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                case .expanded:
                    Label(L10n.tr("accounts.card.switch_to_this"), systemImage: "arrow.left.arrow.right.circle.fill")
                        .lineLimit(1)
                }
            }
        }
        .copoolActionButtonStyle(
            prominent: true,
            tint: .mint,
            density: .compact,
            iOSStyle: .liquidGlass
        )
        .disabled(switching)
        .accessibilityLabel(Text(L10n.tr("accounts.card.switch_to_this")))
    }

    private func windowSection(_ presentation: AccountWindowPresentation, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(presentation.usedText)
                    .font(.caption.weight(.semibold))
                Text(presentation.remainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LiquidProgressBar(progress: presentation.usedPercent / 100, tint: tint)

            Text(presentation.resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func stamp(text: String, tint: Color, fg: Color, maxWidth: CGFloat? = nil) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(fg)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(tint, in: Capsule())
    }

    private var toneColor: Color {
        switch presentation.accent {
        case .orange:
            .orange
        case .pink:
            .pink
        case .gray:
            .gray
        case .indigo:
            .indigo
        case .teal:
            .teal
        }
    }

    private var currentCardSurfaceTint: Color? {
        guard account.isCurrent else { return nil }
        return .teal.opacity(0.14)
    }

    private var canHoverSwitchOverlay: Bool {
        #if os(macOS)
        isCollapsed && !account.isCurrent
        #else
        false
        #endif
    }

    private var canRevealCollapsedSwitchOverlay: Bool {
        isCollapsed && !account.isCurrent && !switching
    }

    private var collapsedSwitchOverlayVisible: Bool {
        guard isCollapsed && !account.isCurrent else { return false }
        #if os(iOS)
        return isCollapsedSwitchOverlayPresented || switching
        #else
        return isHoveringCollapsedSwitch || switching
        #endif
    }

    private func dismissCollapsedSwitchOverlay() {
        guard isCollapsedSwitchOverlayPresented else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isCollapsedSwitchOverlayPresented = false
        }
    }
}

private enum SwitchButtonLabelStyle {
    case iconOnly
    case expanded
}

private struct CompactUsageRing: View {
    let usedPercent: Double?
    let tint: Color

    private var progress: Double {
        guard let usedPercent else { return 0 }
        return max(0, min(1, usedPercent / 100))
    }

    private var percentText: String {
        guard let usedPercent else { return "--" }
        return "\(Int(usedPercent.rounded()))%"
    }

    var body: some View {
        ZStack {
            LiquidProgressRing(
                progress: progress,
                tint: tint,
                lineWidth: 7
            )
            VStack(spacing: 1) {
                Text(percentText)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                Text(L10n.tr("accounts.compact.used"))
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
    }
}
