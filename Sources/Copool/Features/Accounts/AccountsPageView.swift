import SwiftUI

struct AccountsPageView: View {
    @ObservedObject var model: AccountsPageModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                actionBar
                    .padding(.horizontal, LayoutRules.pagePadding)
                contentView
                footerBar
                    .padding(.horizontal, LayoutRules.pagePadding)
            }
            .padding(.top, LayoutRules.pagePadding)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .task {
            await model.loadIfNeeded()
        }
    }

    private var actionBar: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ScrollView(.horizontal) {
                HStack(spacing: LayoutRules.listRowSpacing) {
                    Button {
                        Task { await model.importCurrentAuth() }
                    } label: {
                        Label(model.isImporting ? L10n.tr("accounts.action.importing") : L10n.tr("accounts.action.import_current_auth"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.isImporting || model.isAdding)
                    .buttonStyle(.frostedCapsule(prominent: true))

                    Button {
                        Task { await model.addAccountViaLogin() }
                    } label: {
                        Label(model.isAdding ? L10n.tr("accounts.action.waiting_for_login") : L10n.tr("accounts.action.add_account"), systemImage: "plus")
                    }
                    .disabled(model.isImporting || model.isAdding)
                    .buttonStyle(.frostedCapsule(prominent: true))
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            Button {
                Task { await model.refreshUsage() }
            } label: {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
            }
            .disabled(model.isRefreshing || model.isAdding)
            .buttonStyle(.frostedCapsule(prominent: true, tint: .mint))
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer(minLength: 0)

            Button {
                Task { await model.smartSwitch() }
            } label: {
                Label("accounts.action.smart_switch", systemImage: "wand.and.stars")
            }
            .buttonStyle(.frostedCapsule(prominent: true))
            .disabled(model.isImporting || model.isAdding || model.switchingAccountID != nil)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
        case .empty(let message):
            EmptyStateView(title: L10n.tr("accounts.empty.title"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .error(let message):
            EmptyStateView(title: L10n.tr("accounts.error.load_failed"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .content(let accounts):
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: LayoutRules.accountsRowSpacing) {
                    ForEach(accounts) { account in
                        AccountCardView(
                            account: account,
                            switching: model.switchingAccountID == account.id,
                            onSwitch: { Task { await model.switchAccount(id: account.id) } },
                            onDelete: { Task { await model.deleteAccount(id: account.id) } }
                        )
                        .frame(width: LayoutRules.accountsCardWidth)
                    }
                }
                .padding(.horizontal, LayoutRules.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct AccountCardView: View {
    let account: AccountSummary
    let switching: Bool
    let onSwitch: () -> Void
    let onDelete: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        stamp(text: planLabel, tint: toneColor.opacity(0.18), fg: toneColor)
                        if account.isCurrent {
                            stamp(text: L10n.tr("accounts.card.current"), tint: Color.mint.opacity(0.2), fg: .mint)
                        }
                    }
                    if let teamNameTag {
                        stamp(
                            text: teamNameTag,
                            tint: Color.secondary.opacity(0.16),
                            fg: .secondary,
                            maxWidth: 140
                        )
                    }
                }

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.frostedCapsule(prominent: true, tint: .red))
                .tint(.red)
                .controlSize(.small)
            }

            Text(account.email ?? account.accountID)
                .font(.headline)
                .foregroundStyle(account.isCurrent ? toneColor : .primary)
                .lineLimit(1)

            windowSection(title: L10n.tr("accounts.window.five_hour"), window: account.usage?.fiveHour, tint: .orange)
            windowSection(title: L10n.tr("accounts.window.one_week"), window: account.usage?.oneWeek, tint: .teal)

            HStack(spacing: 8) {
                Text(L10n.tr("accounts.card.credits_format", creditsText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, account.isCurrent ? 0 : 42)
                Spacer(minLength: 0)
            }

            if let usageError = account.usageError, !usageError.isEmpty {
                Text(usageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .cardSurface(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(account.isCurrent ? toneColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if !account.isCurrent {
                Button {
                    onSwitch()
                } label: {
                    if switching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(.frostedCapsule(prominent: true, tint: .mint))
                .controlSize(.small)
                .disabled(switching)
                .accessibilityLabel(Text(L10n.tr("accounts.card.switch_to_this")))
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func windowSection(title: String, window: UsageWindow?, tint: Color) -> some View {
        let usedRaw = clamped(window?.usedPercent)
        let used = roundedPercent(usedRaw)
        let remain = max(0, 100 - used)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(L10n.tr("accounts.window.used_format", percent(used)))
                    .font(.caption.weight(.semibold))
                Text(L10n.tr("accounts.window.remaining_format", percent(remain)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            usageBar(usedPercent: used, tint: tint)

            Text(L10n.tr("accounts.window.reset_at_format", formatResetAt(window?.resetAt)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var planLabel: String {
        let normalized = (account.planType ?? account.usage?.planType ?? "team").lowercased()
        switch normalized {
        case "free": return "FREE"
        case "plus": return "PLUS"
        case "pro": return "PRO"
        case "enterprise": return "ENTERPRISE"
        case "business": return "BUSINESS"
        default: return "TEAM"
        }
    }

    private var teamNameTag: String? {
        guard planLabel == "TEAM" else { return nil }
        return account.displayTeamName
    }

    private var toneColor: Color {
        switch planLabel {
        case "PRO": return .orange
        case "PLUS": return .pink
        case "FREE": return .gray
        case "ENTERPRISE", "BUSINESS": return .indigo
        default: return .teal
        }
    }

    private var creditsText: String {
        guard let credits = account.usage?.credits else { return "--" }
        if credits.unlimited { return L10n.tr("accounts.card.unlimited") }
        return credits.balance ?? "--"
    }

    private func stamp(text: String, tint: Color, fg: Color, maxWidth: CGFloat? = nil) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(fg)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxWidth)
            .background(tint, in: Capsule())
    }

    private func clamped(_ value: Double?) -> Double {
        guard let value else { return 100 }
        return max(0, min(100, value))
    }

    private func roundedPercent(_ value: Double) -> Double {
        Double(Int(value.rounded()))
    }

    private func usageBar(usedPercent: Double, tint: Color) -> some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let ratio = max(0, min(1, usedPercent / 100))
            let fillWidth = totalWidth * ratio

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))

                if fillWidth > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: fillWidth)
                }
            }
        }
        .frame(height: 6)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func formatResetAt(_ epoch: Int64?) -> String {
        guard let epoch else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
