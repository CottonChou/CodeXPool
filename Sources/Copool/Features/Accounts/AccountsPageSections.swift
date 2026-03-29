import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AccountsPageContentSection: View {
    let presentation: AccountsPageContentPresentation
    let cardStoreProvider: (String) -> AccountCardStore?
    let availableViewportSize: CGSize
    let areCardsPresented: Bool
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        switch presentation.state {
        case .loading:
            ProgressView(L10n.tr("accounts.loading.message"))
                .frame(maxWidth: .infinity, minHeight: 180)
        case .empty(let message):
            EmptyStateView(title: L10n.tr("accounts.empty.title"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .error(let message):
            EmptyStateView(title: L10n.tr("accounts.error.load_failed"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .content(let cards):
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                if presentation.shouldShowPendingWorkspaceSection {
                    PendingWorkspaceAuthorizationSection(
                        cards: presentation.pendingWorkspaceCards,
                        errorMessage: presentation.pendingWorkspaceError,
                        areCardsPresented: areCardsPresented,
                        onAuthorizeWorkspace: onAuthorizeWorkspace,
                        onDeletePendingWorkspace: onDeletePendingWorkspace
                    )
                }

                AccountsGridSection(
                    cardIDs: cards,
                    cardStoreProvider: cardStoreProvider,
                    isOverviewMode: presentation.isOverviewMode,
                    availableViewportSize: availableViewportSize,
                    areCardsPresented: areCardsPresented,
                    onSwitchAccount: onSwitchAccount,
                    onRefreshAccountUsage: onRefreshAccountUsage,
                    onDeleteAccount: onDeleteAccount
                )
            }
        }
    }
}

private struct AccountsGridSection: View {
    let cardIDs: [String]
    let cardStoreProvider: (String) -> AccountCardStore?
    let isOverviewMode: Bool
    let availableViewportSize: CGSize
    let areCardsPresented: Bool
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onDeleteAccount: (String) -> Void

    private var gridContext: LayoutRules.AccountsGridContext {
        #if os(iOS)
        LayoutRules.accountsGridContext(
            isOverviewMode: isOverviewMode,
            viewportSize: availableViewportSize
        )
        #else
        LayoutRules.AccountsGridContext(
            platform: .macOS,
            isOverviewMode: isOverviewMode,
            viewportSize: availableViewportSize
        )
        #endif
    }

    private var columns: [GridItem] {
        LayoutRules.accountsGridColumns(context: gridContext)
    }

    private var cardFrameWidth: CGFloat? {
        LayoutRules.accountsCardFrameWidth(context: gridContext)
    }

    private var entries: [AccountCardGridEntry] {
        Array(cardIDs.enumerated()).compactMap { index, cardID in
            guard let cardStore = cardStoreProvider(cardID) else { return nil }
            return AccountCardGridEntry(
                id: cardID,
                store: cardStore,
                areCardsPresented: areCardsPresented,
                frameWidth: cardFrameWidth,
                index: index,
                onSwitch: { onSwitchAccount(cardID) },
                onRefresh: { onRefreshAccountUsage(cardID) },
                onDelete: { onDeleteAccount(cardID) }
            )
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
            MacOSAccountsGridContainer(
                entries: entries,
                columnCount: LayoutRules.accountsGridColumnCount(context: gridContext),
                columnSpacing: LayoutRules.accountsRowSpacing,
                rowSpacing: LayoutRules.accountsRowSpacing
            )
            #else
            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: LayoutRules.accountsRowSpacing
            ) {
                ForEach(entries) { entry in
                    AccountCardGridItem(
                        store: entry.store,
                        areCardsPresented: entry.areCardsPresented,
                        frameWidth: entry.frameWidth,
                        index: entry.index,
                        onSwitch: entry.onSwitch,
                        onRefresh: entry.onRefresh,
                        onDelete: entry.onDelete
                    )
                }
            }
            #endif
        }
        .padding(.horizontal, LayoutRules.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountCardGridEntry: Identifiable {
    let id: String
    let store: AccountCardStore
    let areCardsPresented: Bool
    let frameWidth: CGFloat?
    let index: Int
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void
}

private struct AccountCardGridItem: View {
    @ObservedObject var store: AccountCardStore
    let areCardsPresented: Bool
    let frameWidth: CGFloat?
    let index: Int
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let card = store.presentation
        AccountCardView(
            account: card.account,
            isCollapsed: card.isCollapsed,
            switching: card.switching,
            refreshing: card.refreshing,
            showsRefreshButton: card.showsRefreshButton,
            isRefreshEnabled: card.isRefreshEnabled,
            isUsageRefreshActive: card.isUsageRefreshActive,
            usageProgressDisplayMode: card.usageProgressDisplayMode,
            onSwitch: onSwitch,
            onRefresh: onRefresh,
            onDelete: onDelete
        )
        .frame(width: frameWidth)
        .copoolCardEntrance(index: index, isPresented: areCardsPresented)
        .modifier(AccountCardFrameModifier())
    }
}

private struct CardEntranceModifier: ViewModifier {
    let index: Int
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 22)
            .scaleEffect(isPresented ? 1 : 0.985)
            .animation(
                AccountsAnimationRules.cardEntrance(index: index),
                value: isPresented
            )
    }
}

private extension View {
    func copoolCardEntrance(index: Int, isPresented: Bool) -> some View {
        modifier(CardEntranceModifier(index: index, isPresented: isPresented))
    }
}

private struct AccountCardFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

#if os(macOS)
private struct MacOSAccountsGridContainer: NSViewRepresentable {
    let entries: [AccountCardGridEntry]
    let columnCount: Int
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    func makeNSView(context: Context) -> MacOSAccountsGridHostView {
        let view = MacOSAccountsGridHostView()
        view.update(
            entries: entries,
            columnCount: columnCount,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
        return view
    }

    func updateNSView(_ nsView: MacOSAccountsGridHostView, context: Context) {
        nsView.update(
            entries: entries,
            columnCount: columnCount,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
    }
}

private final class MacOSAccountsGridHostView: NSView {
    private let stack = NSStackView()
    private var rowStacks: [NSStackView] = []
    private var hosts: [String: NSHostingView<AccountCardGridItem>] = [:]
    private var widthConstraints: [String: NSLayoutConstraint] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        configureStack()
    }

    override var isFlipped: Bool {
        true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        entries: [AccountCardGridEntry],
        columnCount: Int,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat
    ) {
        stack.spacing = rowSpacing
        let clampedColumnCount = max(1, columnCount)
        let incomingIDs = Set(entries.map(\.id))

        for (id, host) in hosts where !incomingIDs.contains(id) {
            widthConstraints[id]?.isActive = false
            widthConstraints[id] = nil
            host.removeFromSuperview()
            hosts[id] = nil
        }

        for entry in entries {
            let host = hostView(for: entry)
            host.rootView = makeCardItem(entry: entry)
            applyWidth(entry.frameWidth, to: host, id: entry.id)
        }

        updateRows(
            entries: entries,
            columnCount: clampedColumnCount,
            columnSpacing: columnSpacing
        )
    }

    private func configureStack() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func hostView(for entry: AccountCardGridEntry) -> NSHostingView<AccountCardGridItem> {
        if let existing = hosts[entry.id] {
            return existing
        }
        let host = NSHostingView(rootView: makeCardItem(entry: entry))
        host.translatesAutoresizingMaskIntoConstraints = false
        hosts[entry.id] = host
        return host
    }

    private func makeCardItem(entry: AccountCardGridEntry) -> AccountCardGridItem {
        AccountCardGridItem(
            store: entry.store,
            areCardsPresented: entry.areCardsPresented,
            frameWidth: entry.frameWidth,
            index: entry.index,
            onSwitch: entry.onSwitch,
            onRefresh: entry.onRefresh,
            onDelete: entry.onDelete
        )
    }

    private func applyWidth(_ width: CGFloat?, to host: NSHostingView<AccountCardGridItem>, id: String) {
        if let existing = widthConstraints[id] {
            existing.isActive = false
            widthConstraints[id] = nil
        }
        guard let width else { return }
        let constraint = host.widthAnchor.constraint(equalToConstant: width)
        constraint.priority = .required
        constraint.isActive = true
        widthConstraints[id] = constraint
    }

    private func updateRows(entries: [AccountCardGridEntry], columnCount: Int, columnSpacing: CGFloat) {
        let rowCount = entries.isEmpty ? 0 : Int(ceil(Double(entries.count) / Double(columnCount)))

        while rowStacks.count < rowCount {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fill
            row.translatesAutoresizingMaskIntoConstraints = false
            rowStacks.append(row)
            stack.addArrangedSubview(row)
        }

        while rowStacks.count > rowCount {
            let row = rowStacks.removeLast()
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        for rowIndex in 0..<rowCount {
            let row = rowStacks[rowIndex]
            row.spacing = columnSpacing
            let start = rowIndex * columnCount
            let end = min(start + columnCount, entries.count)
            let targetHosts = entries[start..<end].compactMap { hosts[$0.id] }
            syncRow(row, with: targetHosts)
        }
    }

    private func syncRow(_ row: NSStackView, with targetHosts: [NSView]) {
        let existing = row.arrangedSubviews
        for view in existing where !targetHosts.contains(where: { $0 === view }) {
            row.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, target) in targetHosts.enumerated() {
            if target.superview !== row {
                target.removeFromSuperview()
            }

            if index < row.arrangedSubviews.count {
                if row.arrangedSubviews[index] !== target {
                    if row.arrangedSubviews.contains(where: { $0 === target }) {
                        row.removeArrangedSubview(target)
                        target.removeFromSuperview()
                    }
                    row.insertArrangedSubview(target, at: index)
                }
            } else {
                row.addArrangedSubview(target)
            }
        }

        while row.arrangedSubviews.count > targetHosts.count {
            guard let last = row.arrangedSubviews.last else { break }
            row.removeArrangedSubview(last)
            last.removeFromSuperview()
        }
    }
}
#endif

private struct PendingWorkspaceAuthorizationSection: View {
    let cards: [PendingWorkspaceAuthorizationCardViewState]
    let errorMessage: String?
    let areCardsPresented: Bool
    let onAuthorizeWorkspace: (String) -> Void
    let onDeletePendingWorkspace: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("accounts.pending.title"))
                    .font(.headline)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(L10n.tr("accounts.pending.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, LayoutRules.pagePadding)

            if let errorMessage, cards.isEmpty {
                PendingWorkspaceAuthorizationFailureCard(message: errorMessage)
                    .copoolCardEntrance(index: 0, isPresented: areCardsPresented)
                    .modifier(AccountCardFrameModifier())
                    .padding(.horizontal, LayoutRules.pagePadding)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: LayoutRules.accountsRowSpacing, alignment: .top)],
                    alignment: .leading,
                    spacing: LayoutRules.accountsRowSpacing
                ) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        PendingWorkspaceAuthorizationCard(
                            card: card,
                            onAuthorize: { onAuthorizeWorkspace(card.id) },
                            onDelete: { onDeletePendingWorkspace(card.id) }
                        )
                        .copoolCardEntrance(index: index, isPresented: areCardsPresented)
                        .modifier(AccountCardFrameModifier())
                    }
                }
                .padding(.horizontal, LayoutRules.pagePadding)
            }
        }
    }
}

private struct PendingWorkspaceAuthorizationCard: View {
    let card: PendingWorkspaceAuthorizationCardViewState
    let onAuthorize: () -> Void
    let onDelete: () -> Void

    private var isDeactivated: Bool {
        card.status == .deactivated
    }

    private var planLabel: String {
        AccountSummary(
            id: card.workspaceID,
            label: card.workspaceName,
            email: card.email,
            accountID: card.workspaceID,
            planType: card.planType,
            teamName: card.workspaceName,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: nil,
            usageError: nil,
            isCurrent: false
        ).normalizedPlanLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AccountTagView(
                            text: planLabel,
                            backgroundColor: Color.indigo.opacity(0.18),
                            foregroundColor: .indigo
                        )
                        AccountTagView(
                            text: card.workspaceName,
                            backgroundColor: Color.indigo.opacity(0.18),
                            foregroundColor: .indigo,
                            allowsCompression: true
                        )
                    }

                    if let email = card.email, !email.isEmpty {
                        Text(email)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                AccountTagView(
                    text: isDeactivated ? L10n.tr("accounts.card.status.deactivated") : L10n.tr("accounts.pending.tag"),
                    backgroundColor: isDeactivated ? Color.red.opacity(0.18) : Color.orange.opacity(0.18),
                    foregroundColor: isDeactivated ? .red : .orange
                )
            }

            Text(isDeactivated ? L10n.tr("error.accounts.workspace_deactivated") : L10n.tr("accounts.pending.hint"))
                .font(.caption)
                .foregroundStyle(isDeactivated ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 10) {
                if !isDeactivated && card.deletionMode == .dismissCandidate {
                    Button(action: onAuthorize) {
                        if card.authorizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(L10n.tr("accounts.pending.action.authorize"), systemImage: "checkmark.shield")
                                .lineLimit(1)
                        }
                    }
                    .copoolActionButtonStyle(
                        prominent: true,
                        tint: .indigo,
                        density: .compact,
                        iOSStyle: .liquidGlass
                    )
                    .disabled(card.authorizing)
                }

                Spacer(minLength: 0)

                AccountDeleteButton(action: onDelete, isDisabled: card.authorizing)
                    .accessibilityLabel(L10n.tr("accounts.pending.action.delete"))
            }
        }
        .padding(12)
        .frostedRoundedSurface(
            cornerRadius: 12,
            prominent: true,
            tint: isDeactivated ? .red.opacity(0.18) : .indigo.opacity(0.2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDeactivated ? Color.red.opacity(0.18) : Color.indigo.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct PendingWorkspaceAuthorizationFailureCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                AccountTagView(
                    text: L10n.tr("accounts.pending.error.tag"),
                    backgroundColor: Color.red.opacity(0.18),
                    foregroundColor: .red
                )
                Spacer(minLength: 0)
            }

            Text(L10n.tr("accounts.pending.error.title"))
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.tr("accounts.pending.error.hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frostedRoundedSurface(cornerRadius: 12, prominent: true, tint: .red.opacity(0.18))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
        }
    }
}
