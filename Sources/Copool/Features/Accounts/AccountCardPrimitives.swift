import SwiftUI

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
    let usageError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountWindowSection(presentation: presentation.fiveHourWindow, tint: .orange)
            AccountWindowSection(presentation: presentation.oneWeekWindow, tint: .teal)

            HStack(spacing: 8) {
                Text(L10n.tr("accounts.card.credits_format", presentation.creditsText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 64)
                Spacer(minLength: 0)
            }

            if let usageError, !usageError.isEmpty {
                Text(usageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
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

struct AccountExpandedTrailingOverlay: View {
    let isCollapsed: Bool
    let isCurrent: Bool
    let switching: Bool
    let palette: AccountCardPalette
    let onSwitch: () -> Void

    var body: some View {
        if !isCollapsed {
            if isCurrent {
                AccountTagView(
                    text: L10n.tr("accounts.card.current"),
                    backgroundColor: palette.toneColor.opacity(0.24),
                    foregroundColor: palette.toneColor
                )
                .padding(8)
            } else {
                AccountSwitchButton(
                    switching: switching,
                    labelStyle: .iconOnly,
                    onSwitch: onSwitch
                )
                .padding(8)
            }
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
