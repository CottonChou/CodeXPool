import SwiftUI
import WidgetKit

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
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.18),
                    Color(red: 0.07, green: 0.10, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct AccountsWidgetSmallView: View {
    let card: AccountsWidgetCardSnapshot?

    var body: some View {
        Group {
            if let card {
                AccountsWidgetCompactCard(card: card)
            } else {
                AccountsWidgetEmptyState()
            }
        }
        .padding(14)
    }
}

private struct AccountsWidgetMediumView: View {
    let current: AccountsWidgetCardSnapshot?
    let secondary: AccountsWidgetCardSnapshot?

    var body: some View {
        HStack(spacing: 12) {
            AccountsWidgetCompactCard(card: current)
            AccountsWidgetCompactCard(card: secondary)
        }
        .padding(14)
    }
}

private struct AccountsWidgetLargeView: View {
    let current: AccountsWidgetCardSnapshot?
    let rows: [AccountsWidgetRowSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let current {
                AccountsWidgetCurrentHeader(card: current)
            } else {
                AccountsWidgetEmptyState()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    AccountsWidgetAccountRow(row: row)
                }
            }
        }
        .padding(14)
    }
}

private struct AccountsWidgetCompactCard: View {
    let card: AccountsWidgetCardSnapshot?

    var body: some View {
        Group {
            if let card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        AccountsWidgetChip(text: card.planLabel)
                        if let workspace = card.workspaceLabel, !workspace.isEmpty {
                            AccountsWidgetChip(text: workspace)
                        }
                    }

                    Text(card.accountLabel)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    VStack(spacing: 8) {
                        AccountsWidgetWindowSummary(window: card.fiveHour)
                        AccountsWidgetWindowSummary(window: card.oneWeek)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10))
                }
            } else {
                AccountsWidgetEmptyState()
            }
        }
    }
}

private struct AccountsWidgetCurrentHeader: View {
    let card: AccountsWidgetCardSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AccountsWidgetChip(text: card.planLabel)
                    if let workspace = card.workspaceLabel, !workspace.isEmpty {
                        AccountsWidgetChip(text: workspace)
                    }
                }

                Text(card.accountLabel)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                AccountsWidgetProgressMetric(window: card.fiveHour)
                AccountsWidgetProgressMetric(window: card.oneWeek)
            }
            .frame(width: 132)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        }
    }
}

private struct AccountsWidgetProgressMetric: View {
    let window: AccountsWidgetWindowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "drop.halffull")
                    .font(.system(size: 10, weight: .semibold))
                Text(window.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text(window.remainingText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.88))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.95), Color.teal.opacity(0.75)],
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
    }
}

private struct AccountsWidgetWindowSummary: View {
    let window: AccountsWidgetWindowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(window.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer(minLength: 0)

                Text(window.remainingText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.95), Color.yellow.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * window.progressFraction))
                }
            }
            .frame(height: 6)

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 8, weight: .medium))
                Text(window.resetText)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct AccountsWidgetAccountRow: View {
    let row: AccountsWidgetRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AccountsWidgetChip(text: row.planLabel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.workspaceOrAccountLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let accountLabel = row.accountLabel {
                        Text(accountLabel)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }

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
            Image(systemName: "drop.halffull")
                .font(.system(size: 9, weight: .medium))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
            Text(remainingText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.86))
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
    }
}
