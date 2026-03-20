import SwiftUI

private enum AccountCardOverlayLayout {
    static let actionReservationWidth: CGFloat = 144
}

enum AccountCardMorphRules {
    static let animation = Animation.spring(response: 0.34, dampingFraction: 0.84)
}

enum AccountCardSwitchButtonLabelStyle {
    case iconOnly
    case expanded
}

struct AccountCardPalette {
    let toneColor: Color
    let surfaceTint: Color?

    init(accent: AccountCardAccent, isCurrent: Bool) {
        switch accent {
        case .orange:
            toneColor = .orange
        case .pink:
            toneColor = .pink
        case .gray:
            toneColor = .gray
        case .indigo:
            toneColor = .indigo
        case .teal:
            toneColor = .teal
        }
        surfaceTint = isCurrent ? .teal.opacity(0.14) : nil
    }
}

private struct AccountCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content.cardSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

extension View {
    func accountCardSurface(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil
    ) -> some View {
        modifier(AccountCardSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

struct AccountCardHeaderSection: View {
    let presentation: AccountCardPresentation
    let isCollapsed: Bool
    let isCurrent: Bool
    let palette: AccountCardPalette
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AccountTagView(
                        text: presentation.planLabel,
                        backgroundColor: palette.toneColor.opacity(0.18),
                        foregroundColor: palette.toneColor
                    )
                    if let teamNameTag = presentation.teamNameTag, !isCollapsed {
                        AccountTagView(
                            text: teamNameTag,
                            backgroundColor: palette.toneColor.opacity(0.18),
                            foregroundColor: palette.toneColor
                        )
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
}

struct AccountCardExpandedUsageSection: View {
    let presentation: AccountCardPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountWindowSection(presentation: presentation.fiveHourWindow, tint: .orange)
            AccountWindowSection(presentation: presentation.oneWeekWindow, tint: .teal)

            HStack(spacing: 8) {
                Text(L10n.tr("accounts.card.credits_format", presentation.creditsText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, AccountCardOverlayLayout.actionReservationWidth)
                Spacer(minLength: 0)
            }
        }
    }
}

struct AccountCardCompactUsageSection: View {
    let presentation: AccountCardPresentation

    var body: some View {
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
}

struct AccountCardBottomOverlay: View {
    let isCollapsed: Bool
    let isCurrent: Bool
    let switching: Bool
    let refreshing: Bool
    let isRefreshEnabled: Bool
    let usageError: String?
    let palette: AccountCardPalette
    let onSwitch: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        if !isCollapsed {
            HStack(alignment: .bottom, spacing: 10) {
                if let usageError, !usageError.isEmpty {
                    AccountUsageErrorOverlay(text: usageError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                AccountTrailingActionCluster(
                    isCurrent: isCurrent,
                    switching: switching,
                    refreshing: refreshing,
                    isRefreshEnabled: isRefreshEnabled,
                    palette: palette,
                    onSwitch: onSwitch,
                    onRefresh: onRefresh
                )
            }
            .padding(8)
        }
    }
}

struct AccountCollapsedSwitchOverlay: View {
    let isVisible: Bool
    let switching: Bool
    let onDismiss: () -> Void
    let onSwitch: () -> Void

    var body: some View {
        if isVisible {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
                    .onTapGesture {
                        onDismiss()
                    }

                AccountSwitchButton(
                    switching: switching,
                    labelStyle: .expanded,
                    onSwitch: onSwitch
                )
            }
            .transition(.opacity)
        }
    }
}

struct AccountTagView: View {
    let text: String
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .background(backgroundColor, in: Capsule())
    }
}

private struct AccountWindowSection: View {
    let presentation: AccountWindowPresentation
    let tint: Color

    var body: some View {
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
}

private struct AccountSwitchButton: View {
    let switching: Bool
    let labelStyle: AccountCardSwitchButtonLabelStyle
    let onSwitch: () -> Void

    var body: some View {
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
}

private struct AccountRefreshButton: View {
    let refreshing: Bool
    let isEnabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        Button {
            onRefresh()
        } label: {
            if refreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .copoolActionButtonStyle(
            prominent: true,
            tint: .teal,
            density: .compact,
            iOSStyle: .liquidGlass
        )
        .disabled(!isEnabled)
        .accessibilityLabel(Text(L10n.tr("common.refresh_usage")))
    }
}

private struct AccountTrailingActionCluster: View {
    let isCurrent: Bool
    let switching: Bool
    let refreshing: Bool
    let isRefreshEnabled: Bool
    let palette: AccountCardPalette
    let onSwitch: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isCurrent {
                AccountTagView(
                    text: L10n.tr("accounts.card.current"),
                    backgroundColor: palette.toneColor.opacity(0.24),
                    foregroundColor: palette.toneColor
                )
            } else {
                AccountSwitchButton(
                    switching: switching,
                    labelStyle: .iconOnly,
                    onSwitch: onSwitch
                )
            }

            AccountRefreshButton(
                refreshing: refreshing,
                isEnabled: isRefreshEnabled,
                onRefresh: onRefresh
            )
        }
    }
}

private struct AccountUsageErrorOverlay: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.red)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.red.opacity(0.18), lineWidth: 1)
            }
    }
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
