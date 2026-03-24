import SwiftUI

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
                if !presentation.pendingWorkspaceCards.isEmpty || presentation.pendingWorkspaceError != nil {
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

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: LayoutRules.accountsRowSpacing
        ) {
            ForEach(Array(cardIDs.enumerated()), id: \.element) { index, cardID in
                if let cardStore = cardStoreProvider(cardID) {
                    AccountCardGridItem(
                        store: cardStore,
                        areCardsPresented: areCardsPresented,
                        index: index,
                        onSwitch: { onSwitchAccount(cardID) },
                        onRefresh: { onRefreshAccountUsage(cardID) },
                        onDelete: { onDeleteAccount(cardID) }
                    )
                }
            }
        }
        .animation(
            AccountsAnimationRules.contentReorder,
            value: cardIDs
        )
        .padding(.horizontal, LayoutRules.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountCardGridItem: View {
    @ObservedObject var store: AccountCardStore
    let areCardsPresented: Bool
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

    private var planLabel: String {
        AccountSummary(
            id: card.candidate.workspaceID,
            label: card.candidate.workspaceName,
            email: card.candidate.email,
            accountID: card.candidate.workspaceID,
            planType: card.candidate.planType,
            teamName: card.candidate.workspaceName,
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
                            text: card.candidate.workspaceName,
                            backgroundColor: Color.indigo.opacity(0.18),
                            foregroundColor: .indigo,
                            allowsCompression: true
                        )
                    }

                    if let email = card.candidate.email, !email.isEmpty {
                        Text(email)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                AccountTagView(
                    text: L10n.tr("accounts.pending.tag"),
                    backgroundColor: Color.orange.opacity(0.18),
                    foregroundColor: .orange
                )
            }

            Text(L10n.tr("accounts.pending.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 10) {
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

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.tr("accounts.pending.action.delete"))
                .disabled(card.authorizing)
            }
        }
        .padding(12)
        .frostedRoundedSurface(cornerRadius: 12, prominent: true, tint: .indigo.opacity(0.2))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 1)
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
