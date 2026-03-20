import SwiftUI
import WidgetKit

private enum AccountsWidgetStyle {
    static let defaultVerticalPadding: CGFloat = 14
    static let compactRingLineWidth: CGFloat = 6

    static func layout(for family: WidgetFamily, size: CGSize) -> AccountsWidgetLayout {
        let width = size.width
        let horizontalPadding: CGFloat
        let compactSpacing: CGFloat
        let compactUsageSpacing: CGFloat
        let largeSectionSpacing: CGFloat
        let rowSpacing: CGFloat
        let compactRingSize: CGFloat
        let metricColumnWidth: CGFloat
        let rowMetricColumnWidth: CGFloat

        switch family {
        case .systemSmall:
            horizontalPadding = max(10, min(16, width * 0.08))
            compactSpacing = 10
            compactUsageSpacing = max(10, min(16, width * 0.08))
            largeSectionSpacing = 12
            rowSpacing = 8
            compactRingSize = max(40, min(52, width * 0.26))
            metricColumnWidth = max(118, min(160, width * 0.72))
            rowMetricColumnWidth = max(76, min(96, width * 0.30))
        case .systemMedium:
            horizontalPadding = max(12, min(18, width * 0.05))
            compactSpacing = max(10, min(14, width * 0.025))
            compactUsageSpacing = max(12, min(18, width * 0.04))
            largeSectionSpacing = 12
            rowSpacing = 8
            compactRingSize = max(42, min(56, width * 0.18))
            metricColumnWidth = max(124, min(172, width * 0.37))
            rowMetricColumnWidth = max(80, min(100, width * 0.19))
        default:
            horizontalPadding = max(8, min(14, width * 0.025))
            compactSpacing = 12
            compactUsageSpacing = 14
            largeSectionSpacing = 14
            rowSpacing = 10
            compactRingSize = 48
            metricColumnWidth = max(136, min(180, width * 0.30))
            rowMetricColumnWidth = max(84, min(112, width * 0.18))
        }

        return AccountsWidgetLayout(
            horizontalPadding: horizontalPadding,
            verticalPadding: defaultVerticalPadding,
            compactSpacing: compactSpacing,
            compactUsageSpacing: compactUsageSpacing,
            largeSectionSpacing: largeSectionSpacing,
            rowSpacing: rowSpacing,
            compactRingSize: compactRingSize,
            metricColumnWidth: metricColumnWidth,
            rowMetricColumnWidth: rowMetricColumnWidth
        )
    }

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.13, blue: 0.18),
            Color(red: 0.07, green: 0.10, blue: 0.14),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct AccountsWidgetLayout {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let compactSpacing: CGFloat
    let compactUsageSpacing: CGFloat
    let largeSectionSpacing: CGFloat
    let rowSpacing: CGFloat
    let compactRingSize: CGFloat
    let metricColumnWidth: CGFloat
    let rowMetricColumnWidth: CGFloat
}

struct AccountsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AccountsWidgetEntry

    var body: some View {
        GeometryReader { proxy in
            let layout = AccountsWidgetStyle.layout(for: family, size: proxy.size)

            Group {
                switch family {
                case .systemSmall:
                    AccountsWidgetSmallView(card: entry.snapshot.currentCard, layout: layout)
                case .systemMedium:
                    AccountsWidgetMediumView(
                        current: entry.snapshot.currentCard,
                        secondary: entry.snapshot.secondaryCard,
                        layout: layout
                    )
                default:
                    AccountsWidgetLargeView(
                        current: entry.snapshot.currentCard,
                        rows: entry.snapshot.rows,
                        layout: layout
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            AccountsWidgetStyle.backgroundGradient
        }
    }
}

private struct AccountsWidgetSmallView: View {
    let card: AccountsWidgetCardSnapshot?
    let layout: AccountsWidgetLayout

    var body: some View {
        Group {
            if let card {
                AccountsWidgetCompactCardContent(card: card, layout: layout)
            } else {
                AccountsWidgetEmptyState()
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }
}

private struct AccountsWidgetMediumView: View {
    let current: AccountsWidgetCardSnapshot?
    let secondary: AccountsWidgetCardSnapshot?
    let layout: AccountsWidgetLayout

    var body: some View {
        HStack(spacing: layout.compactSpacing) {
            Group {
                if let current {
                    AccountsWidgetCompactCardContent(card: current, layout: layout)
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
                    AccountsWidgetCompactCardContent(card: secondary, layout: layout)
                } else {
                    AccountsWidgetEmptyState()
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }
}

private struct AccountsWidgetLargeView: View {
    let current: AccountsWidgetCardSnapshot?
    let rows: [AccountsWidgetRowSnapshot]
    let layout: AccountsWidgetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.largeSectionSpacing) {
            if let current {
                AccountsWidgetCurrentHeader(card: current, layout: layout)
            } else {
                AccountsWidgetEmptyState()
            }

            VStack(alignment: .leading, spacing: layout.rowSpacing) {
                ForEach(rows) { row in
                    AccountsWidgetAccountRow(row: row, layout: layout)
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }
}

private struct AccountsWidgetCompactCardContent: View {
    let card: AccountsWidgetCardSnapshot
    let layout: AccountsWidgetLayout

    private var workspaceOrFallbackLabel: String {
        if let workspaceLabel = card.workspaceLabel, !workspaceLabel.isEmpty {
            return workspaceLabel
        }
        return card.accountLabel
    }

    private var shouldShowAccountLabel: Bool {
        card.workspaceLabel?.isEmpty ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountsWidgetChip(text: workspaceOrFallbackLabel)

            if shouldShowAccountLabel {
                Text(card.accountLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: layout.compactUsageSpacing) {
                AccountsWidgetCompactUsageRing(window: card.fiveHour, tint: .orange, layout: layout)
                AccountsWidgetCompactUsageRing(window: card.oneWeek, tint: .teal, layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AccountsWidgetCurrentHeader: View {
    let card: AccountsWidgetCardSnapshot
    let layout: AccountsWidgetLayout

    private var workspaceOrFallbackLabel: String {
        if let workspaceLabel = card.workspaceLabel, !workspaceLabel.isEmpty {
            return workspaceLabel
        }
        return card.accountLabel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AccountsWidgetChip(text: workspaceOrFallbackLabel)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                AccountsWidgetProgressMetric(window: card.fiveHour, tint: .orange, layout: layout)
                AccountsWidgetProgressMetric(window: card.oneWeek, tint: .teal, layout: layout)
            }
            .frame(width: layout.metricColumnWidth)
        }
    }
}

private struct AccountsWidgetCompactUsageRing: View {
    let window: AccountsWidgetWindowSnapshot
    let tint: Color
    let layout: AccountsWidgetLayout

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
            .frame(width: layout.compactRingSize, height: layout.compactRingSize)
        }
    }
}

private struct AccountsWidgetProgressMetric: View {
    let window: AccountsWidgetWindowSnapshot
    let tint: Color
    let layout: AccountsWidgetLayout

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
        .frame(width: layout.metricColumnWidth, alignment: .leading)
    }
}

private struct AccountsWidgetAccountRow: View {
    let row: AccountsWidgetRowSnapshot
    let layout: AccountsWidgetLayout

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AccountsWidgetChip(text: row.workspaceOrAccountLabel)
                .fixedSize(horizontal: true, vertical: false)

            AccountsWidgetRowMetricColumn(
                title: "5h",
                remainingText: row.fiveHourRemainingText,
                resetText: row.fiveHourResetText,
                layout: layout
            )

            AccountsWidgetRowMetricColumn(
                title: "1w",
                remainingText: row.oneWeekRemainingText,
                resetText: row.oneWeekResetText,
                layout: layout
            )
        }
    }
}

private struct AccountsWidgetRowMetricColumn: View {
    let title: String
    let remainingText: String
    let resetText: String
    let layout: AccountsWidgetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .medium))
                Text(resetText)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }

        .foregroundStyle(.white.opacity(0.86))
        .frame(width: layout.rowMetricColumnWidth, alignment: .leading)
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
