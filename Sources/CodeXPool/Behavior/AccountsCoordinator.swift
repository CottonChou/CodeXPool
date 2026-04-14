import Foundation

actor AccountsCoordinator {
    enum UsageRefreshPolicy {
        static let minimumRefreshIntervalSeconds: Int64 = 25

        static func shouldRefresh(_ snapshot: UsageSnapshot?, now: Int64) -> Bool {
            guard let snapshot else { return true }
            return now - snapshot.fetchedAt >= minimumRefreshIntervalSeconds
        }
    }

    let storeRepository: AccountsStoreRepository
    let settingsRepository: SettingsRepository
    let authRepository: AuthRepository
    let usageService: UsageService
    let workspaceMetadataService: WorkspaceMetadataService?
    let chatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol
    let codexCLIService: CodexCLIServiceProtocol
    let editorAppService: EditorAppServiceProtocol
    let opencodeAuthSyncService: OpencodeAuthSyncServiceProtocol
    let configTomlService: ConfigTomlServiceProtocol
    let claudeConfigService: ClaudeConfigServiceProtocol
    let authBackupService: AuthBackupServiceProtocol
    let dateProvider: DateProviding
    let runtimePlatform: RuntimePlatform

    init(
        storeRepository: AccountsStoreRepository,
        settingsRepository: SettingsRepository,
        authRepository: AuthRepository,
        usageService: UsageService,
        workspaceMetadataService: WorkspaceMetadataService? = nil,
        chatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol,
        codexCLIService: CodexCLIServiceProtocol,
        editorAppService: EditorAppServiceProtocol,
        opencodeAuthSyncService: OpencodeAuthSyncServiceProtocol,
        configTomlService: ConfigTomlServiceProtocol,
        claudeConfigService: ClaudeConfigServiceProtocol,
        authBackupService: AuthBackupServiceProtocol,
        dateProvider: DateProviding = SystemDateProvider(),
        runtimePlatform: RuntimePlatform = PlatformCapabilities.currentPlatform
    ) {
        self.storeRepository = storeRepository
        self.settingsRepository = settingsRepository
        self.authRepository = authRepository
        self.usageService = usageService
        self.workspaceMetadataService = workspaceMetadataService
        self.chatGPTOAuthLoginService = chatGPTOAuthLoginService
        self.codexCLIService = codexCLIService
        self.editorAppService = editorAppService
        self.opencodeAuthSyncService = opencodeAuthSyncService
        self.configTomlService = configTomlService
        self.claudeConfigService = claudeConfigService
        self.authBackupService = authBackupService
        self.dateProvider = dateProvider
        self.runtimePlatform = runtimePlatform
    }

    func deleteAccount(id: String) throws {
        var store = try storeRepository.loadStore()
        store.accounts.removeAll { $0.id == id }
        try storeRepository.saveStore(store)
    }

    func listWorkspaceDirectory() throws -> [WorkspaceDirectoryEntry] {
        try storeRepository.loadStore().workspaceDirectory
    }

    func updateWorkspaceDirectoryVisibility(
        workspaceID: String,
        visibility: WorkspaceDirectoryVisibility
    ) throws {
        var store = try storeRepository.loadStore()
        let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(workspaceID)
        guard !normalizedWorkspaceID.isEmpty else { return }
        guard let index = store.workspaceDirectory.firstIndex(where: {
            AccountIdentity.normalizedAccountID($0.workspaceID) == normalizedWorkspaceID
        }) else {
            return
        }
        store.workspaceDirectory[index].visibility = visibility
        try storeRepository.saveStore(store)
    }

    func updateWorkspaceDirectoryStatus(
        workspaceID: String,
        workspaceName: String,
        email: String?,
        planType: String?,
        kind: WorkspaceDirectoryKind,
        status: WorkspaceDirectoryStatus
    ) throws {
        var store = try storeRepository.loadStore()
        let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(workspaceID)
        guard !normalizedWorkspaceID.isEmpty else { return }
        let now = dateProvider.unixSecondsNow()
        let entry = WorkspaceDirectoryEntry(
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            email: email,
            planType: planType,
            kind: kind,
            source: status == .deactivated ? .deactivated : .consent,
            status: status,
            visibility: .visible,
            lastSeenAt: now,
            lastStatusCheckedAt: now
        )

        if let index = store.workspaceDirectory.firstIndex(where: {
            AccountIdentity.normalizedAccountID($0.workspaceID) == normalizedWorkspaceID
        }) {
            store.workspaceDirectory[index] = entry
        } else {
            store.workspaceDirectory.append(entry)
        }
        try storeRepository.saveStore(store)
    }

    func updateTeamAlias(id: String, alias: String?) throws -> AccountSummary {
        var store = try storeRepository.loadStore()
        guard let index = store.accounts.firstIndex(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_update"))
        }

        store.accounts[index].teamAlias = normalizeTeamAlias(alias)
        store.accounts[index].updatedAt = dateProvider.unixSecondsNow()
        try storeRepository.saveStore(store)

        return toSummary(store.accounts[index], currentAccountKey: authRepository.currentAuthAccountKey())
    }

    func switchAccount(id: String) throws {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try updateCurrentAccountProjection(authJSON: account.authJSON)
    }

    func switchAccountAndApplySettings(id: String, workspacePath: String? = nil) throws -> SwitchAccountExecutionResult {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try updateCurrentAccountProjection(authJSON: account.authJSON)
        authRepository.invalidateReadCache()
        let settings = try settingsRepository.loadSettings()
        return try applySwitchSideEffects(
            for: account,
            settings: settings,
            workspacePath: workspacePath
        )
    }

    func smartSwitch() async throws -> (AccountSummary, SwitchAccountExecutionResult)? {
        let sorted = AccountRanking.sortByRemaining(try await listAccounts())
        guard let best = sorted.first else { return nil }
        let execution = try switchAccountAndApplySettings(id: best.id)
        return (best, execution)
    }

    func autoSmartSwitchIfNeeded() async throws -> (AccountSummary, SwitchAccountExecutionResult)? {
        let accounts = try await listAccounts()
        guard let target = AccountRanking.pickAutoSwitchTarget(accounts) else {
            return nil
        }
        let execution = try switchAccountAndApplySettings(id: target.id)
        return (target, execution)
    }

    private func updateCurrentAccountProjection(authJSON: JSONValue) throws {
        let extracted = try authRepository.extractAuth(from: authJSON)
        var store = try storeRepository.loadStore()
        guard let matchedAccount = Self.matchingStoredAccount(for: extracted, in: store.accounts) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        store.currentSelection = CurrentAccountSelection(
            accountID: extracted.accountID,
            selectedAt: dateProvider.unixMillisecondsNow(),
            sourceDeviceID: runtimePlatform == .macOS ? "macos-local" : "ios-local",
            accountKey: matchedAccount.accountKey
        )
        try storeRepository.saveStore(store)
        try authRepository.writeCurrentAuth(authJSON)
    }

    private func normalizeTeamAlias(_ alias: String?) -> String? {
        guard let alias else { return nil }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applySwitchSideEffects(
        for account: StoredAccount,
        settings: AppSettings,
        workspacePath: String?
    ) throws -> SwitchAccountExecutionResult {
        var result = SwitchAccountExecutionResult.idle

        if settings.syncOpencodeOpenaiAuth {
            do {
                try opencodeAuthSyncService.syncFromCodexAuth(account.authJSON)
                result.opencodeSynced = true
            } catch {
                result.opencodeSyncError = error.localizedDescription
            }
        }

        guard runtimePlatform == .macOS else {
            return result
        }

        if settings.restartEditorsOnSwitch {
            let restart = editorAppService.restartSelectedApps(settings.restartEditorTargets)
            result.restartedEditorApps = restart.restarted
            result.editorRestartError = restart.error
        }

        if settings.launchCodexAfterSwitch {
            result.usedFallbackCLI = try codexCLIService.launchApp(workspacePath: workspacePath)
        }

        return result
    }

    static func matchingStoredAccountIndex(
        for extracted: ExtractedAuth,
        in accounts: [StoredAccount]
    ) -> Int? {
        AccountIdentity.preferredMatchIndex(for: extracted, in: accounts)
    }

    static func matchingStoredAccount(
        for extracted: ExtractedAuth,
        in accounts: [StoredAccount]
    ) -> StoredAccount? {
        guard let index = matchingStoredAccountIndex(for: extracted, in: accounts) else {
            return nil
        }
        return accounts[index]
    }

    // MARK: - API Key Profiles

    func listAPIKeyProfiles() throws -> [APIKeyProfile] {
        let store = try storeRepository.loadStore()
        let currentID = store.currentAPIKeySelection?.profileID
        return store.apiKeyProfiles.map { profile in
            var p = profile
            p.isCurrent = (store.activeAuthMode == .apiKey && p.id == currentID)
            return p
        }
    }

    func addAPIKeyProfile(_ profile: APIKeyProfile) throws -> APIKeyProfile {
        var store = try storeRepository.loadStore()
        var newProfile = profile
        if newProfile.id.isEmpty {
            newProfile.id = UUID().uuidString
        }
        newProfile.addedAt = dateProvider.unixSecondsNow()
        newProfile.updatedAt = newProfile.addedAt
        store.apiKeyProfiles.append(newProfile)
        try storeRepository.saveStore(store)
        return newProfile
    }

    func updateAPIKeyProfile(_ profile: APIKeyProfile) throws -> APIKeyProfile {
        var store = try storeRepository.loadStore()
        guard let index = store.apiKeyProfiles.firstIndex(where: { $0.id == profile.id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_update"))
        }
        var updated = profile
        updated.updatedAt = dateProvider.unixSecondsNow()
        store.apiKeyProfiles[index] = updated
        try storeRepository.saveStore(store)
        return updated
    }

    func deleteAPIKeyProfile(id: String) throws {
        var store = try storeRepository.loadStore()
        store.apiKeyProfiles.removeAll { $0.id == id }
        if store.currentAPIKeySelection?.profileID == id {
            store.currentAPIKeySelection = nil
        }
        try storeRepository.saveStore(store)
    }

    func activeAuthMode() throws -> ActiveAuthMode {
        try storeRepository.loadStore().activeAuthMode
    }

    func switchToAPIKeyProfile(id: String, workspacePath: String? = nil) throws -> SwitchAccountExecutionResult {
        var store = try storeRepository.loadStore()
        guard let profile = store.apiKeyProfiles.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try authBackupService.backupCurrentAuthFiles()
        try configTomlService.writeForAPIKeyMode(profile: profile)
        authRepository.invalidateReadCache()
        ChatGPTBaseOriginResolver.invalidateCache()

        store.activeAuthMode = .apiKey
        store.currentAPIKeySelection = APIKeySelection(
            profileID: profile.id,
            selectedAt: dateProvider.unixMillisecondsNow()
        )
        try storeRepository.saveStore(store)

        #if os(macOS)
        let resolvedProvider = ConfigTomlService.resolvedProviderName(for: profile)
        let repairService = CodexThreadRepairService()
        _ = repairService.repairThreadVisibility(
            targetProvider: resolvedProvider,
            targetModel: profile.model
        )
        #endif

        let settings = try settingsRepository.loadSettings()
        return try applySwitchSideEffectsForAPIKey(
            profile: profile,
            settings: settings,
            workspacePath: workspacePath
        )
    }

    func switchToChatGPTAccount(id: String, workspacePath: String? = nil) throws -> SwitchAccountExecutionResult {
        var store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try authBackupService.backupCurrentAuthFiles()
        try configTomlService.writeForChatGPTMode()
        authRepository.invalidateReadCache()
        ChatGPTBaseOriginResolver.invalidateCache()

        store.activeAuthMode = .chatgpt
        try storeRepository.saveStore(store)

        try updateCurrentAccountProjection(authJSON: account.authJSON)

        #if os(macOS)
        let repairService = CodexThreadRepairService()
        _ = repairService.repairThreadVisibility(targetProvider: "openai")
        #endif

        let settings = try settingsRepository.loadSettings()
        return try applySwitchSideEffects(
            for: account,
            settings: settings,
            workspacePath: workspacePath
        )
    }

    private func applySwitchSideEffectsForAPIKey(
        profile: APIKeyProfile,
        settings: AppSettings,
        workspacePath: String?
    ) throws -> SwitchAccountExecutionResult {
        var result = SwitchAccountExecutionResult.idle

        guard runtimePlatform == .macOS else {
            return result
        }

        if settings.restartEditorsOnSwitch {
            let restart = editorAppService.restartSelectedApps(settings.restartEditorTargets)
            result.restartedEditorApps = restart.restarted
            result.editorRestartError = restart.error
        }

        if settings.launchCodexAfterSwitch {
            result.usedFallbackCLI = try codexCLIService.launchApp(
                workspacePath: workspacePath
            )
        }

        return result
    }

    // MARK: - Claude API Key Profiles

    func listClaudeAPIKeyProfiles() throws -> [ClaudeAPIKeyProfile] {
        let store = try storeRepository.loadStore()
        let savedID = store.currentClaudeAPIKeySelection?.profileID

        let hasSavedMatch = savedID != nil &&
            store.claudeAPIKeyProfiles.contains { $0.id == savedID }

        if hasSavedMatch {
            return store.claudeAPIKeyProfiles.map { profile in
                var p = profile
                p.isCurrent = (p.id == savedID)
                return p
            }
        }

        let liveKey = claudeConfigService.readCurrentAPIKey()
        let liveURL = claudeConfigService.readCurrentBaseURL()

        return store.claudeAPIKeyProfiles.map { profile in
            var p = profile
            p.isCurrent = liveKey != nil && p.apiKey == liveKey && p.baseURL == (liveURL ?? "")
            return p
        }
    }

    func addClaudeAPIKeyProfile(_ profile: ClaudeAPIKeyProfile) throws -> ClaudeAPIKeyProfile {
        var store = try storeRepository.loadStore()
        var newProfile = profile
        if newProfile.id.isEmpty {
            newProfile.id = UUID().uuidString
        }
        newProfile.addedAt = dateProvider.unixSecondsNow()
        newProfile.updatedAt = newProfile.addedAt
        store.claudeAPIKeyProfiles.append(newProfile)
        try storeRepository.saveStore(store)
        return newProfile
    }

    func updateClaudeAPIKeyProfile(_ profile: ClaudeAPIKeyProfile) throws -> ClaudeAPIKeyProfile {
        var store = try storeRepository.loadStore()
        guard let index = store.claudeAPIKeyProfiles.firstIndex(where: { $0.id == profile.id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_update"))
        }
        var updated = profile
        updated.updatedAt = dateProvider.unixSecondsNow()
        store.claudeAPIKeyProfiles[index] = updated
        try storeRepository.saveStore(store)
        return updated
    }

    func deleteClaudeAPIKeyProfile(id: String) throws {
        var store = try storeRepository.loadStore()
        store.claudeAPIKeyProfiles.removeAll { $0.id == id }
        if store.currentClaudeAPIKeySelection?.profileID == id {
            store.currentClaudeAPIKeySelection = nil
        }
        try storeRepository.saveStore(store)
    }

    func switchToClaudeAPIKeyProfile(id: String) throws {
        var store = try storeRepository.loadStore()
        guard let profile = store.claudeAPIKeyProfiles.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try claudeConfigService.writeForAPIKeyMode(profile: profile)

        store.currentClaudeAPIKeySelection = ClaudeAPIKeySelection(
            profileID: profile.id,
            selectedAt: dateProvider.unixMillisecondsNow()
        )
        try storeRepository.saveStore(store)
    }
}
