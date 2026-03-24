import Foundation

extension AccountsCoordinator {
    func listAccounts() async throws -> [AccountSummary] {
        var store = try storeRepository.loadStore()
        let didReconcile = Self.reconcileStoredAccountMetadata(in: &store, authRepository: authRepository)
        let didEnrich = await enrichStoredWorkspaceMetadataIfNeeded(in: &store, forceRemoteCheck: false)
        if didReconcile || didEnrich {
            try storeRepository.saveStore(store)
        }
        return store.accountSummaries(currentAccountKey: authRepository.currentAuthAccountKey())
    }

    @discardableResult
    func importCurrentAuthAccount(customLabel: String?) async throws -> AccountSummary {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        let authJSON = try authRepository.readCurrentAuth()
        return try await importAccount(authJSON: authJSON, customLabel: customLabel)
    }

    @discardableResult
    func importAccountFile(from url: URL, customLabel: String?, setAsCurrent: Bool) async throws -> AccountSummary {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let authJSON = try authRepository.readAuth(from: url)
        if setAsCurrent, runtimePlatform == .macOS {
            try authRepository.writeCurrentAuth(authJSON)
        }
        return try await importAccount(authJSON: authJSON, customLabel: customLabel)
    }

    @discardableResult
    func addAccountViaLogin(customLabel: String?, timeoutSeconds: TimeInterval = 10 * 60) async throws -> AccountSummary {
        let tokens = try await chatGPTOAuthLoginService.signInWithChatGPT(timeoutSeconds: timeoutSeconds)
        let authJSON = try authRepository.makeChatGPTAuth(from: tokens)
        return try await importAccount(authJSON: authJSON, customLabel: customLabel)
    }

    func discoverPendingWorkspaceAuthorizations(sourceAccountID: String) async throws -> [WorkspaceAuthorizationCandidate] {
        guard runtimePlatform == .macOS else { return [] }
        guard let workspaceMetadataService else { return [] }

        let store = try storeRepository.loadStore()
        guard let sourceAccount = store.accounts.first(where: { $0.id == sourceAccountID }) else {
            return []
        }

        let extracted = try authRepository.extractAuth(from: sourceAccount.authJSON)
        let metadata = try await workspaceMetadataService.fetchWorkspaceMetadata(accessToken: extracted.accessToken)
        let existingWorkspaceIDs = Set(store.accounts.map { AccountIdentity.normalizedAccountID($0.accountID) })
        let ignoredWorkspaceIDs = Set(store.ignoredPendingWorkspaceIDs.map(AccountIdentity.normalizedAccountID))

        return metadata.compactMap { workspace in
            let workspaceID = AccountIdentity.normalizedAccountID(workspace.accountID)
            guard !workspaceID.isEmpty else { return nil }
            guard !existingWorkspaceIDs.contains(workspaceID) else { return nil }
            guard !ignoredWorkspaceIDs.contains(workspaceID) else { return nil }
            guard let trimmedWorkspaceName = Self.visibleWorkspaceName(for: workspace) else { return nil }

            return WorkspaceAuthorizationCandidate(
                workspaceID: workspace.accountID,
                workspaceName: trimmedWorkspaceName,
                email: sourceAccount.email ?? extracted.email,
                planType: sourceAccount.planType ?? extracted.planType
            )
        }
        .sorted { lhs, rhs in
            lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
        }
    }

    @discardableResult
    func authorizeWorkspaceViaLogin(
        workspaceID: String,
        workspaceName: String,
        customLabel: String?,
        timeoutSeconds: TimeInterval = 10 * 60
    ) async throws -> AccountSummary {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        let tokens = try await chatGPTOAuthLoginService.signInWithChatGPT(
            timeoutSeconds: timeoutSeconds,
            forcedWorkspaceID: workspaceID
        )
        let authJSON = try authRepository.makeChatGPTAuth(from: tokens)
        return try await importAccount(
            authJSON: authJSON,
            customLabel: customLabel,
            prefetchedWorkspaceName: workspaceName
        )
    }

    func refreshUsage(
        accountIDs: [String]? = nil,
        force: Bool = false,
        serial: Bool = false,
        onPartialUpdate: (@Sendable ([AccountSummary]) async -> Void)? = nil
    ) async throws -> [AccountSummary] {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        let now = dateProvider.unixSecondsNow()
        let snapshot = try storeRepository.loadStore()
        let authRepository = self.authRepository
        let usageService = self.usageService
        let currentAccountKey = authRepository.currentAuthAccountKey()
        let targetIDSet = accountIDs.map(Set.init)
        let refreshTargets = snapshot.accounts.filter { account in
            guard let targetIDSet else { return true }
            return targetIDSet.contains(account.id)
        }

        guard !refreshTargets.isEmpty else {
            return snapshot.accountSummaries(currentAccountKey: authRepository.currentAuthAccountKey())
        }

        var latest = snapshot
        if serial {
            for account in refreshTargets {
                let refreshed = await Self.refreshAccount(
                    account,
                    now: now,
                    forceRefresh: force,
                    currentAccountKey: currentAccountKey,
                    authRepository: authRepository,
                    usageService: usageService
                )
                latest = Self.mergeRefreshedAccount(refreshed, into: latest)
                try storeRepository.saveStore(latest)
                if let onPartialUpdate {
                    await onPartialUpdate(
                        latest.accountSummaries(currentAccountKey: authRepository.currentAuthAccountKey())
                    )
                }
            }
        } else {
            try await withThrowingTaskGroup(of: StoredAccount.self, returning: Void.self) { group in
                for account in refreshTargets {
                    group.addTask {
                        await Self.refreshAccount(
                            account,
                            now: now,
                            forceRefresh: force,
                            currentAccountKey: currentAccountKey,
                            authRepository: authRepository,
                            usageService: usageService
                        )
                    }
                }
                for try await refreshed in group {
                    latest = Self.mergeRefreshedAccount(refreshed, into: latest)
                    try storeRepository.saveStore(latest)
                    if let onPartialUpdate {
                        await onPartialUpdate(
                            latest.accountSummaries(currentAccountKey: authRepository.currentAuthAccountKey())
                        )
                    }
                }
            }
        }

        return latest.accountSummaries(currentAccountKey: authRepository.currentAuthAccountKey())
    }

    func refreshWorkspaceMetadata(forceRemoteCheck: Bool) async throws -> [AccountSummary] {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        var store = try storeRepository.loadStore()
        let didChange = await enrichStoredWorkspaceMetadataIfNeeded(
            in: &store,
            forceRemoteCheck: forceRemoteCheck
        )
        if didChange {
            try storeRepository.saveStore(store)
        }
        return store.accountSummaries(currentAccountKey: authRepository.currentAuthAccountKey())
    }

    private func importAccount(
        authJSON: JSONValue,
        customLabel: String?,
        prefetchedWorkspaceName: String? = nil
    ) async throws -> AccountSummary {
        let now = dateProvider.unixSecondsNow()
        let currentAccountKey = authRepository.currentAuthAccountKey()
        var authJSON = authJSON
        var extracted = try authRepository.extractAuth(from: authJSON)
        if let prefetchedWorkspaceName {
            extracted.teamName = prefetchedWorkspaceName
        } else if runtimePlatform == .macOS,
           let remoteWorkspaceName = await resolveRemoteWorkspaceName(for: extracted, forceRemoteCheck: true) {
            extracted.teamName = remoteWorkspaceName
        }

        var usage: UsageSnapshot?
        var usageError: String?

        if runtimePlatform == .macOS {
            do {
                let refreshed = try await Self.fetchUsageSnapshot(
                    authJSON: authJSON,
                    authRepository: authRepository,
                    usageService: usageService,
                    now: now
                )
                authJSON = refreshed.authJSON
                extracted = refreshed.extractedAuth
                if let prefetchedWorkspaceName {
                    extracted.teamName = prefetchedWorkspaceName
                } else if let remoteWorkspaceName = await resolveRemoteWorkspaceName(for: extracted, forceRemoteCheck: true) {
                    extracted.teamName = remoteWorkspaceName
                }
                usage = refreshed.usage
            } catch {
                usageError = error.localizedDescription
            }
        }

        let generatedLabel = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = generatedLabel?.isEmpty == false
            ? generatedLabel!
            : (extracted.email ?? "Codex \(String(extracted.accountID.prefix(8)))")

        var store = try storeRepository.loadStore()
        let account = StoredAccount(
            id: UUID().uuidString,
            label: label,
            email: extracted.email,
            accountID: extracted.accountID,
            planType: extracted.planType,
            teamName: extracted.teamName,
            teamAlias: nil,
            authJSON: authJSON,
            addedAt: now,
            updatedAt: now,
            usage: usage,
            usageError: usageError,
            usageStateUpdatedAt: usage == nil && usageError == nil ? 0 : now,
            workspaceStatus: .active,
            principalID: extracted.principalID
        )

        if let existingIndex = Self.matchingStoredAccountIndex(for: extracted, in: store.accounts) {
            var existing = store.accounts[existingIndex]
            existing.label = account.label
            existing.email = account.email
            existing.planType = account.planType
            if let teamName = Self.normalizedTeamName(account.teamName) {
                existing.teamName = teamName
            }
            existing.authJSON = account.authJSON
            existing.updatedAt = now
            existing.usage = usage ?? existing.usage
            existing.usageError = usageError
            if usage != nil || usageError != nil {
                existing.usageStateUpdatedAt = now
            }
            existing.workspaceStatus = .active
            existing.principalID = extracted.principalID
            store.accounts[existingIndex] = existing
        } else {
            store.accounts.append(account)
        }
        store.ignoredPendingWorkspaceIDs.removeAll {
            AccountIdentity.normalizedAccountID($0) == AccountIdentity.normalizedAccountID(extracted.accountID)
        }

        try storeRepository.saveStore(store)
        Self.persistCurrentAuthIfNeeded(
            authJSON,
            extracted: extracted,
            currentAccountKey: currentAccountKey,
            authRepository: authRepository
        )
        let savedAccount = Self.matchingStoredAccount(for: extracted, in: store.accounts)!
        return toSummary(savedAccount, currentAccountKey: authRepository.currentAuthAccountKey())
    }

    func toSummary(_ account: StoredAccount, currentAccountKey: String?) -> AccountSummary {
        AccountsStore(accounts: [account]).accountSummaries(currentAccountKey: currentAccountKey)[0]
    }

    private func resolveRemoteWorkspaceName(
        for extracted: ExtractedAuth,
        forceRemoteCheck: Bool
    ) async -> String? {
        guard let workspaceMetadataService else { return nil }
        guard shouldLookupRemoteWorkspaceMetadata(extracted: extracted) else {
            return extracted.teamName
        }
        guard forceRemoteCheck || Self.normalizedTeamName(extracted.teamName) == nil else {
            return extracted.teamName
        }
        guard let directory = try? await workspaceMetadataService.fetchWorkspaceMetadata(
            accessToken: extracted.accessToken
        ) else {
            return extracted.teamName
        }
        return Self.remoteWorkspaceName(for: extracted.accountID, in: directory) ?? extracted.teamName
    }

    private func enrichStoredWorkspaceMetadataIfNeeded(
        in store: inout AccountsStore,
        forceRemoteCheck: Bool
    ) async -> Bool {
        guard let workspaceMetadataService else { return false }

        var didChange = false
        var cachedDirectories: [String: [WorkspaceMetadata]] = [:]

        for index in store.accounts.indices {
            let storedAccount = store.accounts[index]
            guard let extracted = try? authRepository.extractAuth(from: storedAccount.authJSON) else { continue }
            guard shouldLookupRemoteWorkspaceMetadata(extracted: extracted) else { continue }

            let directory: [WorkspaceMetadata]
            if let cached = cachedDirectories[extracted.accessToken] {
                directory = cached
            } else {
                guard let fetched = try? await workspaceMetadataService.fetchWorkspaceMetadata(
                    accessToken: extracted.accessToken
                ) else { continue }
                cachedDirectories[extracted.accessToken] = fetched
                directory = fetched
            }

            guard let remoteWorkspace = Self.remoteWorkspaceSnapshot(
                for: extracted.accountID,
                in: directory
            ) else { continue }

            if let remoteWorkspaceName = remoteWorkspace.name,
               store.accounts[index].teamName != remoteWorkspaceName {
                store.accounts[index].teamName = remoteWorkspaceName
                didChange = true
            }

            if store.accounts[index].workspaceStatus != remoteWorkspace.status {
                store.accounts[index].workspaceStatus = remoteWorkspace.status
                didChange = true
            }
        }

        return didChange
    }

    private func shouldLookupRemoteWorkspaceMetadata(extracted: ExtractedAuth) -> Bool {
        let normalizedPlan = (extracted.planType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedPlan == "team" || normalizedPlan == "business" || normalizedPlan == "enterprise"
    }

    private static func refreshAccount(
        _ account: StoredAccount,
        now: Int64,
        forceRefresh: Bool,
        currentAccountKey: String?,
        authRepository: AuthRepository,
        usageService: UsageService
    ) async -> StoredAccount {
        var account = account
        guard forceRefresh || UsageRefreshPolicy.shouldRefresh(account.usage, now: now) else {
            return account
        }

        do {
            let refreshed = try await fetchUsageSnapshot(
                authJSON: account.authJSON,
                authRepository: authRepository,
                usageService: usageService,
                now: now
            )
            account.authJSON = refreshed.authJSON
            account.usage = refreshed.usage
            account.usageError = nil
            account.usageStateUpdatedAt = now
            account.planType = refreshed.extractedAuth.planType ?? account.planType
            if let teamName = normalizedTeamName(refreshed.extractedAuth.teamName) {
                account.teamName = teamName
            }
            account.email = refreshed.extractedAuth.email ?? account.email
            account.workspaceStatus = .active
            account.principalID = refreshed.extractedAuth.principalID
            persistCurrentAuthIfNeeded(
                refreshed.authJSON,
                extracted: refreshed.extractedAuth,
                currentAccountKey: currentAccountKey,
                authRepository: authRepository
            )
        } catch {
            account.usageError = error.localizedDescription
            account.usageStateUpdatedAt = now
        }

        account.updatedAt = now
        return account
    }

    private static func mergeRefreshedAccount(
        _ refreshed: StoredAccount,
        into store: AccountsStore
    ) -> AccountsStore {
        var store = store
        store.accounts = store.accounts.map { existing in
            guard existing.id == refreshed.id else { return existing }
            var merged = existing
            merged.label = refreshed.label
            merged.email = refreshed.email
            merged.planType = refreshed.planType
            merged.teamName = refreshed.teamName
            merged.teamAlias = refreshed.teamAlias
            merged.authJSON = refreshed.authJSON
            merged.updatedAt = refreshed.updatedAt
            merged.usage = refreshed.usage
            merged.usageError = refreshed.usageError
            merged.workspaceStatus = refreshed.workspaceStatus
            merged.principalID = refreshed.principalID
            return merged
        }
        return store
    }

    private static func refreshAuthIfNeeded(
        _ authJSON: JSONValue,
        authRepository: AuthRepository,
        now: Int64
    ) async throws -> JSONValue {
        guard accessTokenIsExpired(in: authJSON, now: now) else {
            return authJSON
        }
        return try await authRepository.refreshChatGPTAuth(authJSON)
    }

    private static func fetchUsageSnapshot(
        authJSON: JSONValue,
        authRepository: AuthRepository,
        usageService: UsageService,
        now: Int64
    ) async throws -> (authJSON: JSONValue, extractedAuth: ExtractedAuth, usage: UsageSnapshot) {
        var authJSON = try await refreshAuthIfNeeded(
            authJSON,
            authRepository: authRepository,
            now: now
        )
        var extracted = try authRepository.extractAuth(from: authJSON)

        do {
            let usage = try await usageService.fetchUsage(
                accessToken: extracted.accessToken,
                accountID: extracted.accountID
            )
            return (authJSON, extracted, usage)
        } catch {
            guard isExpiredAuthenticationError(error) else {
                throw error
            }

            authJSON = try await authRepository.refreshChatGPTAuth(authJSON)
            extracted = try authRepository.extractAuth(from: authJSON)
            let usage = try await usageService.fetchUsage(
                accessToken: extracted.accessToken,
                accountID: extracted.accountID
            )
            return (authJSON, extracted, usage)
        }
    }

    private static func accessTokenIsExpired(in authJSON: JSONValue, now: Int64) -> Bool {
        guard let accessToken = AuthJWTDecoder.tokenObject(from: authJSON)?["access_token"]?.stringValue,
              let claims = try? AuthJWTDecoder.decodePayload(accessToken),
              let expiration = claims["exp"]?.int64Value else {
            return false
        }
        return expiration <= now
    }

    private static func isExpiredAuthenticationError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("provided authentication token is expired")
            || message.contains("token_expired")
            || message.contains("signing in again")
    }

    private static func persistCurrentAuthIfNeeded(
        _ authJSON: JSONValue,
        extracted: ExtractedAuth,
        currentAccountKey: String?,
        authRepository: AuthRepository
    ) {
        guard let currentAccountKey,
              currentAccountKey == AccountIdentity.key(for: extracted) else {
            return
        }
        try? authRepository.writeCurrentAuth(authJSON)
    }

    private static func reconcileStoredAccountMetadata(
        in store: inout AccountsStore,
        authRepository: AuthRepository
    ) -> Bool {
        var didChange = false

        for index in store.accounts.indices {
            let storedAccount = store.accounts[index]
            guard let reconciled = try? authRepository.extractAuth(from: storedAccount.authJSON) else {
                continue
            }

            if store.accounts[index].email != reconciled.email {
                store.accounts[index].email = reconciled.email
                didChange = true
            }

            if store.accounts[index].principalID != reconciled.principalID {
                store.accounts[index].principalID = reconciled.principalID
                didChange = true
            }

            if store.accounts[index].planType != reconciled.planType {
                store.accounts[index].planType = reconciled.planType
                didChange = true
            }

            let reconciledTeamName = normalizedTeamName(reconciled.teamName)
            let storedTeamName = normalizedTeamName(store.accounts[index].teamName)
            if let reconciledTeamName, storedTeamName != reconciledTeamName {
                store.accounts[index].teamName = reconciledTeamName
                didChange = true
            }
        }

        return didChange
    }

    private static func normalizedTeamName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func remoteWorkspaceName(
        for accountID: String,
        in metadata: [WorkspaceMetadata]
    ) -> String? {
        remoteWorkspaceSnapshot(for: accountID, in: metadata)?.name
    }

    private static func remoteWorkspaceSnapshot(
        for accountID: String,
        in metadata: [WorkspaceMetadata]
    ) -> (name: String?, status: AccountWorkspaceStatus)? {
        guard let match = metadata.first(where: {
            AccountIdentity.normalizedAccountID($0.accountID) == AccountIdentity.normalizedAccountID(accountID)
        }) else {
            return nil
        }

        let trimmedName = normalizedTeamName(match.workspaceName)
        if workspaceMetadataRepresentsInactiveWorkspace(match) {
            return (trimmedName, .deactivated)
        }

        guard let visibleName = visibleWorkspaceName(for: match) else {
            return nil
        }

        return (visibleName, .active)
    }

    private static func visibleWorkspaceName(for metadata: WorkspaceMetadata) -> String? {
        if workspaceMetadataRepresentsInactiveWorkspace(metadata) || workspaceMetadataIsPersonal(metadata) {
            return nil
        }

        guard let trimmedName = metadata.workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty else {
            return nil
        }

        return trimmedName
    }

    private static func workspaceMetadataRepresentsInactiveWorkspace(_ metadata: WorkspaceMetadata) -> Bool {
        let inactiveKeywords = ["deactivat", "disabl", "archiv", "suspend", "inactive", "deleted"]
        return workspaceMetadataContainsAnyKeyword(metadata, keywords: inactiveKeywords)
    }

    private static func workspaceMetadataIsPersonal(_ metadata: WorkspaceMetadata) -> Bool {
        workspaceMetadataContainsAnyKeyword(metadata, keywords: ["personal"])
    }

    private static func workspaceMetadataContainsAnyKeyword(
        _ metadata: WorkspaceMetadata,
        keywords: [String]
    ) -> Bool {
        let searchableFields = [
            metadata.structure,
            metadata.workspaceName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for field in searchableFields where !field.isEmpty {
            if keywords.contains(where: { field.contains($0) }) {
                return true
            }
        }
        return false
    }

}
