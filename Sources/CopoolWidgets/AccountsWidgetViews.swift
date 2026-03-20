import SwiftUI
import WidgetKit

private enum AccountsWidgetStyle {
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 14
    static let largeHorizontalPadding: CGFloat = 10
    static let compactSpacing: CGFloat = 12
    static let compactUsageSpacing: CGFloat = 14
    static let largeSectionSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 10
    static let compactRingSize: CGFloat = 48
    static let compactRingLineWidth: CGFloat = 6
    static let metricColumnWidth: CGFloat = 156
    static let rowMetricColumnWidth: CGFloat = 88

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.13, blue: 0.18),
            Color(red: 0.07, green: 0.10, blue: 0.14),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AccountsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AccountsWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                AccountsWidgetSmallView(card: entry.snapshot.currentCard)
            case .systemMedium:
                AccountsWidgetMediumView(
                    current: entry.snapshot.currentCard,
                    secondary: entry.snapshot.secondaryCard
                )
            default:
                AccountsWidgetLargeView(
                    current: entry.snapshot.currentCard,
                    rows: entry.snapshot.rows
                )
            }
        }
        .containerBackground(for: .widget) {
            AccountsWidgetStyle.backgroundGradient
        }
    }
}

private struct AccountsWidgetSmallView: View {
    let card: AccountsWidgetCardSnapshot?

    var body: some View {
        Group {
            if let card {
                AccountsWidgetCompactCardContent(card: card, roleLabel: "current")
            } else {
                AccountsWidgetEmptyState()
            }
        }
        .padding(.horizontal, AccountsWidgetStyle.horizontalPadding)
        .padding(.vertical, AccountsWidgetStyle.verticalPadding)
    }
}

private struct AccountsWidgetMediumView: View {
    let current: AccountsWidgetCardSnapshot?
    let secondary: AccountsWidgetCardSnapshot?

    var body: some View {
        HStack(spacing: AccountsWidgetStyle.compactSpacing) {
            Group {
                if let current {
                    AccountsWidgetCompactCardContent(card: current, roleLabel: "current")
                } else {
                    AccountsWidgetEmptyState()
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 4)

            Group {
                if let secondary {
                    AccountsWidgetCompactCardContent(card: secondary, roleLabel: "next")
                } else {
                    AccountsWidgetEmptyState()
                }
            }
        }
        .padding(.horizontal, AccountsWidgetStyle.horizontalPadding)
        .padding(.vertical, AccountsWidgetStyle.verticalPadding)
    }
}

private struct AccountsWidgetLargeView: View {
    let current: AccountsWidgetCardSnapshot?
    let rows: [AccountsWidgetRowSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: AccountsWidgetStyle.largeSectionSpacing) {
            if let current {
                AccountsWidgetCurrentHeader(card: current)
            } else {
                AccountsWidgetEmptyState()
            }

            VStack(alignment: .leading, spacing: AccountsWidgetStyle.rowSpacing) {
                ForEach(rows) { row in
                    AccountsWidgetAccountRow(row: row)
                }
            }
        }
        .padding(.horizontal, AccountsWidgetStyle.largeHorizontalPadding)
        .padding(.vertical, AccountsWidgetStyle.verticalPadding)
    }
}

private struct AccountsWidgetCompactCardContent: View {
    let card: AccountsWidgetCardSnapshot
    let roleLabel: String

    private var workspaceOrFallbackLabel: String {
        if let workspaceLabel = card.workspaceLabel, !workspaceLabel.isEmpty {
            return workspaceLabel
        }
        return card.accountLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                AccountsWidgetChip(text: workspaceOrFallbackLabel)
                Spacer(minLength: 0)
                AccountsWidgetRoleBadge(text: roleLabel)
            }

            Text(card.accountLabel)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: AccountsWidgetStyle.compactUsageSpacing) {
                AccountsWidgetCompactUsageRing(window: card.fiveHour, tint: .orange)
                AccountsWidgetCompactUsageRing(window: card.oneWeek, tint: .teal)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AccountsWidgetCurrentHeader: View {
    let card: AccountsWidgetCardSnapshot

    private var workspaceOrFallbackLabel: String {
        if let workspaceLabel = card.workspaceLabel, !workspaceLabel.isEmpty {
            return workspaceLabel
        }
        return card.accountLabel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    AccountsWidgetChip(text: workspaceOrFallbackLabel)
                    Spacer(minLength: 0)
                    AccountsWidgetRoleBadge(text: "current")
                }

                Text(card.accountLabel)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                AccountsWidgetProgressMetric(window: card.fiveHour, tint: .orange)
                AccountsWidgetProgressMetric(window: card.oneWeek, tint: .teal)
            }
            .frame(width: 150)
        }
    }
}

private struct AccountsWidgetCompactUsageRing: View {
    let window: AccountsWidgetWindowSnapshot
    let tint: Color

    private var progress: Double {
        min(max(window.progressFraction, 0), 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: AccountsWidgetStyle.compactRingLineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [tint.opacity(0.95), tint.opacity(0.65)]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: AccountsWidgetStyle.compactRingLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(window.usedText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(window.title)
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(width: AccountsWidgetStyle.compactRingSize, height: AccountsWidgetStyle.compactRingSize)
        }
    }
}

private struct AccountsWidgetProgressMetric: View {
    let window: AccountsWidgetWindowSnapshot
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                Text(window.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 10, weight: .semibold))
                    Text(window.remainingText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white.opacity(0.88))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.95), tint.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, proxy.size.width * window.progressFraction))
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .medium))
                Text(window.resetText)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white.opacity(0.62))
        }
        .frame(width: AccountsWidgetStyle.metricColumnWidth, alignment: .leading)
    }
}

private struct AccountsWidgetAccountRow: View {
    let row: AccountsWidgetRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AccountsWidgetChip(text: row.workspaceOrAccountLabel)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    AccountsWidgetRowMetric(title: "5h", remainingText: row.fiveHourRemainingText)
                    AccountsWidgetRowMetric(title: "1w", remainingText: row.oneWeekRemainingText)
                }
            }

            HStack(spacing: 10) {
                AccountsWidgetResetLine(text: row.fiveHourResetText)
                AccountsWidgetResetLine(text: row.oneWeekResetText)
            }
        }
    }
}

private struct AccountsWidgetRowMetric: View {
    let title: String
    let remainingText: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .medium))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Image(systemName: "drop.halffull")
                    .font(.system(size: 9, weight: .medium))
                Text(remainingText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white.opacity(0.86))
        .frame(width: AccountsWidgetStyle.rowMetricColumnWidth, alignment: .leading)
    }
}

private struct AccountsWidgetResetLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white.opacity(0.58))
        .frame(width: AccountsWidgetStyle.rowMetricColumnWidth, alignment: .leading)
    }
}

private struct AccountsWidgetChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(Color.cyan.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.cyan.opacity(0.14))
            )
    }
}

private struct AccountsWidgetRoleBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
            .textCase(.lowercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            }
    }
}

private struct AccountsWidgetEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Accounts")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Open Copool to sync account usage into the widget.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
