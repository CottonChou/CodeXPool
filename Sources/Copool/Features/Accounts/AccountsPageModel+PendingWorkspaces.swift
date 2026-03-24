import Foundation

extension AccountsPageModel {
    func authorizePendingWorkspace(id: String) async {
        guard runtimePlatform == .macOS else {
            notice = NoticeMessage(style: .error, text: PlatformCapabilities.unsupportedOperationMessage)
            return
        }
        guard !isRefreshing, !isAdding, !isImporting else { return }
        guard let candidate = pendingWorkspaceAuthorizations.first(where: { $0.id == id }) else { return }

        authorizingWorkspaceID = id
        defer { authorizingWorkspaceID = nil }

        do {
            let imported = try await coordinator.authorizeWorkspaceViaLogin(
                workspaceID: candidate.workspaceID,
                workspaceName: candidate.workspaceName,
                customLabel: nil
            )
            removePendingWorkspaceAuthorization(id: id)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishAndSyncLocalAccountsMutation(accounts)
            schedulePendingWorkspaceRefresh(
                from: accounts,
                preferredSourceAccountID: imported.id
            )
            notice = NoticeMessage(
                style: .success,
                text: L10n.tr("accounts.notice.workspace_authorized_format", candidate.workspaceName)
            )
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deletePendingWorkspace(id: String) async {
        guard runtimePlatform == .macOS else {
            notice = NoticeMessage(style: .error, text: PlatformCapabilities.unsupportedOperationMessage)
            return
        }
        guard authorizingWorkspaceID != id else { return }
        guard pendingWorkspaceAuthorizations.contains(where: { $0.id == id }) else { return }

        do {
            try await coordinator.dismissPendingWorkspaceAuthorization(workspaceID: id)
            removePendingWorkspaceAuthorization(id: id)
            notice = NoticeMessage(style: .info, text: L10n.tr("accounts.pending.notice.dismissed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshPendingWorkspaceAuthorizations(
        from accounts: [AccountSummary],
        preferredSourceAccountID: String? = nil
    ) async {
        guard runtimePlatform == .macOS else {
            pendingWorkspaceAuthorizations = []
            pendingWorkspaceAuthorizationError = nil
            return
        }

        let sourceAccountIDs = pendingWorkspaceAuthorizationSourceAccountIDs(
            from: accounts,
            preferredSourceAccountID: preferredSourceAccountID
        )
        guard !sourceAccountIDs.isEmpty else {
            pendingWorkspaceAuthorizations = []
            pendingWorkspaceAuthorizationError = nil
            return
        }

        var mergedCandidatesByID: [String: WorkspaceAuthorizationCandidate] = [:]
        for sourceAccountID in sourceAccountIDs {
            guard !Task.isCancelled else { return }
            do {
                let candidates = try await coordinator.discoverPendingWorkspaceAuthorizations(
                    sourceAccountID: sourceAccountID
                )
                guard !Task.isCancelled else { return }
                for candidate in candidates {
                    mergedCandidatesByID[candidate.workspaceID] = candidate
                }
            } catch {
                guard !isPendingWorkspaceRefreshCancellation(error) else { return }
                _ = error
            }
        }

        let mergedCandidates = mergedCandidatesByID.values.sorted {
            $0.workspaceName.localizedCaseInsensitiveCompare($1.workspaceName) == .orderedAscending
        }
        pendingWorkspaceAuthorizations = mergedCandidates
        pendingWorkspaceAuthorizationError = nil
    }

    func schedulePendingWorkspaceRefresh(
        from accounts: [AccountSummary],
        preferredSourceAccountID: String? = nil
    ) {
        pendingWorkspaceRefreshTask?.cancel()
        pendingWorkspaceRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshPendingWorkspaceAuthorizations(
                from: accounts,
                preferredSourceAccountID: preferredSourceAccountID
            )
        }
    }

    func clearPendingWorkspaceAuthorizations() {
        pendingWorkspaceAuthorizations = []
        pendingWorkspaceAuthorizationError = nil
        authorizingWorkspaceID = nil
    }

    private func removePendingWorkspaceAuthorization(id: String) {
        pendingWorkspaceAuthorizations.removeAll { $0.id == id }
        pendingWorkspaceAuthorizationError = nil
    }

    private func isPendingWorkspaceRefreshCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return error.localizedDescription.lowercased().contains("cancelled")
    }

    private func pendingWorkspaceAuthorizationSourceAccountIDs(
        from accounts: [AccountSummary],
        preferredSourceAccountID: String?
    ) -> [String] {
        var orderedIDs: [String] = []

        if let preferredSourceAccountID,
           accounts.contains(where: { $0.id == preferredSourceAccountID }) {
            orderedIDs.append(preferredSourceAccountID)
        }

        if let currentID = accounts.first(where: \.isCurrent)?.id,
           !orderedIDs.contains(currentID) {
            orderedIDs.append(currentID)
        }

        for account in accounts where !orderedIDs.contains(account.id) {
            orderedIDs.append(account.id)
        }

        return orderedIDs
    }
}
