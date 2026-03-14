import Foundation
import CryptoKit

actor AccountsCoordinator {
    private let storeRepository: AccountsStoreRepository
    private let authRepository: AuthRepository
    private let usageService: UsageService
    private let codexCLIService: CodexCLIServiceProtocol
    private let editorAppService: EditorAppServiceProtocol
    private let opencodeAuthSyncService: OpencodeAuthSyncServiceProtocol
    private let dateProvider: DateProviding

    init(
        storeRepository: AccountsStoreRepository,
        authRepository: AuthRepository,
        usageService: UsageService,
        codexCLIService: CodexCLIServiceProtocol,
        editorAppService: EditorAppServiceProtocol,
        opencodeAuthSyncService: OpencodeAuthSyncServiceProtocol,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.storeRepository = storeRepository
        self.authRepository = authRepository
        self.usageService = usageService
        self.codexCLIService = codexCLIService
        self.editorAppService = editorAppService
        self.opencodeAuthSyncService = opencodeAuthSyncService
        self.dateProvider = dateProvider
    }

    func listAccounts() throws -> [AccountSummary] {
        let store = try storeRepository.loadStore()
        let currentAccountID = authRepository.currentAuthAccountID()
        return mapToSummaries(store: store, currentAccountID: currentAccountID)
    }

    @discardableResult
    func importCurrentAuthAccount(customLabel: String?) async throws -> AccountSummary {
        let authJSON = try authRepository.readCurrentAuth()
        let extracted = try authRepository.extractAuth(from: authJSON)

        var usage: UsageSnapshot?
        var usageError: String?

        do {
            usage = try await usageService.fetchUsage(accessToken: extracted.accessToken, accountID: extracted.accountID)
        } catch {
            usageError = error.localizedDescription
        }

        let now = dateProvider.unixSecondsNow()
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
            usageError: usageError
        )

        if let existingIndex = store.accounts.firstIndex(where: { $0.accountID == extracted.accountID }) {
            var existing = store.accounts[existingIndex]
            existing.label = account.label
            existing.email = account.email
            existing.planType = account.planType
            existing.teamName = account.teamName
            existing.authJSON = account.authJSON
            existing.updatedAt = now
            existing.usage = usage ?? existing.usage
            existing.usageError = usageError
            store.accounts[existingIndex] = existing
        } else {
            store.accounts.append(account)
        }

        try storeRepository.saveStore(store)
        let savedAccount = store.accounts.first(where: { $0.accountID == extracted.accountID })!

        let currentAccountID = authRepository.currentAuthAccountID()
        return toSummary(savedAccount, currentAccountID: currentAccountID)
    }

    func deleteAccount(id: String) throws {
        var store = try storeRepository.loadStore()
        store.accounts.removeAll { $0.id == id }
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

        return toSummary(store.accounts[index], currentAccountID: authRepository.currentAuthAccountID())
    }

    func switchAccount(id: String) throws {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try authRepository.writeCurrentAuth(account.authJSON)
    }

    func switchAccountAndApplySettings(id: String, workspacePath: String? = nil) throws -> SwitchAccountExecutionResult {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        try authRepository.writeCurrentAuth(account.authJSON)

        var result = SwitchAccountExecutionResult.idle
        let settings = store.settings

        if settings.syncOpencodeOpenaiAuth {
            do {
                try opencodeAuthSyncService.syncFromCodexAuth(account.authJSON)
                result.opencodeSynced = true
            } catch {
                result.opencodeSyncError = error.localizedDescription
            }
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

    func smartSwitch() throws -> (AccountSummary, SwitchAccountExecutionResult)? {
        let sorted = AccountRanking.sortByRemaining(try listAccounts())
        guard let best = sorted.first else { return nil }
        let execution = try switchAccountAndApplySettings(id: best.id)
        return (best, execution)
    }

    func autoSmartSwitchIfNeeded() throws -> (AccountSummary, SwitchAccountExecutionResult)? {
        let accounts = try listAccounts()
        guard let target = AccountRanking.pickAutoSwitchTarget(accounts) else {
            return nil
        }
        let execution = try switchAccountAndApplySettings(id: target.id)
        return (target, execution)
    }

    func addAccountViaLogin(customLabel: String?, timeoutSeconds: TimeInterval = 10 * 60) async throws -> AccountSummary {
        let backupAuth = try authRepository.readCurrentAuthOptional()
        let baselineFingerprint = fingerprint(of: backupAuth)

        defer {
            try? restoreAuth(backupAuth)
        }

        try codexCLIService.launchLogin()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(2500))
            let currentAuth = try authRepository.readCurrentAuthOptional()
            guard let currentAuth else { continue }
            let currentFingerprint = fingerprint(of: currentAuth)
            guard currentFingerprint != baselineFingerprint else { continue }
            return try await importCurrentAuthAccount(customLabel: customLabel)
        }

        throw AppError.io(L10n.tr("error.accounts.add_account_timeout"))
    }

    func refreshAllUsage() async throws -> [AccountSummary] {
        let now = dateProvider.unixSecondsNow()
        let snapshot = try storeRepository.loadStore()

        var refreshedAccounts: [StoredAccount] = []
        refreshedAccounts.reserveCapacity(snapshot.accounts.count)

        for var account in snapshot.accounts {
            do {
                let extracted = try authRepository.extractAuth(from: account.authJSON)
                let usage = try await usageService.fetchUsage(accessToken: extracted.accessToken, accountID: extracted.accountID)
                account.usage = usage
                account.usageError = nil
                account.planType = extracted.planType ?? account.planType
                account.teamName = extracted.teamName
                account.email = extracted.email ?? account.email
            } catch {
                account.usageError = error.localizedDescription
            }
            account.updatedAt = now
            refreshedAccounts.append(account)
        }

        var latest = try storeRepository.loadStore()
        let refreshedByAccountID = Dictionary(uniqueKeysWithValues: refreshedAccounts.map { ($0.accountID, $0) })

        latest.accounts = latest.accounts.map { existing in
            guard let refreshed = refreshedByAccountID[existing.accountID] else {
                return existing
            }
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
            return merged
        }

        try storeRepository.saveStore(latest)

        return mapToSummaries(store: latest, currentAccountID: authRepository.currentAuthAccountID())
    }

    private func mapToSummaries(store: AccountsStore, currentAccountID: String?) -> [AccountSummary] {
        store.accounts.map { toSummary($0, currentAccountID: currentAccountID) }
    }

    private func toSummary(_ account: StoredAccount, currentAccountID: String?) -> AccountSummary {
        AccountSummary(
            id: account.id,
            label: account.label,
            email: account.email,
            accountID: account.accountID,
            planType: account.planType,
            teamName: account.teamName,
            teamAlias: account.teamAlias,
            addedAt: account.addedAt,
            updatedAt: account.updatedAt,
            usage: account.usage,
            usageError: account.usageError,
            isCurrent: currentAccountID == account.accountID
        )
    }

    private func restoreAuth(_ backupAuth: JSONValue?) throws {
        if let backupAuth {
            try authRepository.writeCurrentAuth(backupAuth)
        } else {
            try authRepository.removeCurrentAuth()
        }
    }

    private func fingerprint(of auth: JSONValue?) -> String? {
        guard let auth else { return nil }
        let object = auth.toAny()
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizeTeamAlias(_ alias: String?) -> String? {
        guard let alias else { return nil }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
