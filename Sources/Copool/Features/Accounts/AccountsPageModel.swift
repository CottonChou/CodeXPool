import Foundation
import Combine

@MainActor
final class AccountsPageModel: ObservableObject {
    let coordinator: AccountsCoordinator
    let settingsCoordinator: SettingsCoordinator?
    let manualRefreshService: AccountsManualRefreshServiceProtocol?
    let localAccountsMutationSyncService: AccountsLocalMutationSyncServiceProtocol?
    let currentAccountSelectionSyncService: CurrentAccountSelectionSyncServiceProtocol?
    let cloudSyncAvailabilityService: CloudSyncAvailabilityService?
    let chooseAuthDocumentURL: (() -> URL?)?
    let onLocalAccountsChanged: (([AccountSummary]) -> Void)?
    let onSettingsUpdated: ((AppSettings) -> Void)?
    let runtimePlatform: RuntimePlatform

    private let noticeScheduler = NoticeAutoDismissScheduler()
    var pendingWorkspaceRefreshTask: Task<Void, Never>?
    var addAccountTask: Task<AccountSummary, Error>?
    var pendingWorkspaceAuthorizationTask: Task<AccountSummary, Error>?

    var hasLoaded = false
    var isCloudSyncAvailable = true
    @Published var usageProgressDisplayMode: UsageProgressDisplayMode

    @Published var state: ViewState<[AccountSummary]>
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }
    @Published var isManualRefreshing = false
    @Published var isRemoteUsageRefreshing = false
    @Published var remoteUsageRefreshingAccountIDs: Set<String> = []
    @Published var isImporting = false
    @Published var isAdding = false
    @Published var switchingAccountID: String?
    @Published var refreshingAccountIDs: Set<String> = []
    @Published var collapsedAccountIDs: Set<String> = []
    @Published var workspaceDirectory: [WorkspaceDirectoryEntry] = []
    @Published var pendingWorkspaceAuthorizations: [WorkspaceAuthorizationCandidate] = []
    @Published var pendingWorkspaceAuthorizationError: String?
    @Published var authorizingWorkspaceID: String?

    @Published var activeAuthMode: ActiveAuthMode = .chatgpt
    @Published var apiKeyProfiles: [APIKeyProfile] = []
    @Published var switchingAPIKeyProfileID: String?
    @Published var isEditingAPIKeyProfile = false
    @Published var editingAPIKeyProfile: APIKeyProfile?

    init(
        coordinator: AccountsCoordinator,
        settingsCoordinator: SettingsCoordinator? = nil,
        manualRefreshService: AccountsManualRefreshServiceProtocol? = nil,
        localAccountsMutationSyncService: AccountsLocalMutationSyncServiceProtocol? = nil,
        currentAccountSelectionSyncService: CurrentAccountSelectionSyncServiceProtocol? = nil,
        cloudSyncAvailabilityService: CloudSyncAvailabilityService? = nil,
        chooseAuthDocumentURL: (() -> URL?)? = nil,
        runtimePlatform: RuntimePlatform = PlatformCapabilities.currentPlatform,
        usageProgressDisplayMode: UsageProgressDisplayMode = .used,
        onLocalAccountsChanged: (([AccountSummary]) -> Void)? = nil,
        onSettingsUpdated: ((AppSettings) -> Void)? = nil,
        initialAccounts: [AccountSummary]? = nil
    ) {
        self.coordinator = coordinator
        self.settingsCoordinator = settingsCoordinator
        self.manualRefreshService = manualRefreshService
        self.localAccountsMutationSyncService = localAccountsMutationSyncService
        self.currentAccountSelectionSyncService = currentAccountSelectionSyncService
        self.cloudSyncAvailabilityService = cloudSyncAvailabilityService
        self.chooseAuthDocumentURL = chooseAuthDocumentURL
        self.runtimePlatform = runtimePlatform
        self.usageProgressDisplayMode = usageProgressDisplayMode
        self.onLocalAccountsChanged = onLocalAccountsChanged
        self.onSettingsUpdated = onSettingsUpdated
        self.state = initialAccounts.map { initialAccounts in
            Self.makeViewState(
                accounts: AccountRanking.sortForDisplay(initialAccounts),
                cloudSyncAvailable: true
            )
        } ?? .loading
    }

    var canRefreshUsageAction: Bool {
        !isAdding
    }

    var areAllAccountsCollapsed: Bool {
        guard case .content(let accounts) = state else { return false }
        let ids = Set(accounts.filter { !$0.isWorkspaceDeactivated }.map(\.id))
        guard !ids.isEmpty else { return false }
        return collapsedAccountIDs.isSuperset(of: ids)
    }

    var hasResolvedInitialState: Bool {
        if case .loading = state {
            return false
        }
        return true
    }

    var isRefreshing: Bool {
        isManualRefreshing || isRemoteUsageRefreshing || !refreshingAccountIDs.isEmpty
    }

    var isRefreshSpinnerActive: Bool {
        isManualRefreshing
    }

    deinit {
        addAccountTask?.cancel()
        pendingWorkspaceAuthorizationTask?.cancel()
        pendingWorkspaceRefreshTask?.cancel()
    }

    var desktopActionButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>] {
        AccountsActionPresentation.desktopButtons(
            isImporting: isImporting,
            isAdding: isAdding,
            switchingAccountID: switchingAccountID,
            canRefreshUsage: canRefreshUsageAction,
            isRefreshSpinnerActive: isRefreshSpinnerActive
        )
    }

    var leadingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>] {
        let buttons = AccountsActionPresentation.leadingToolbarButtons(
            isImporting: isImporting,
            isAdding: isAdding
        )
        guard runtimePlatform == .iOS else { return buttons }
        return buttons.filter { $0.intent != .importCurrentAuth }
    }

    var trailingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>] {
        AccountsActionPresentation.trailingToolbarButtons(
            canRefreshUsage: canRefreshUsageAction,
            isRefreshSpinnerActive: isRefreshSpinnerActive,
            areAllAccountsCollapsed: areAllAccountsCollapsed
        )
    }

    var collapsePresentation: AccountsCollapsePresentation {
        AccountsActionPresentation.collapseControl(
            areAllAccountsCollapsed: areAllAccountsCollapsed
        )
    }

    func isAccountCollapsed(_ id: String) -> Bool {
        collapsedAccountIDs.contains(id)
    }

    func isAccountRefreshing(_ id: String) -> Bool {
        refreshingAccountIDs.contains(id)
    }

    func canRefreshAccount(_ id: String) -> Bool {
        runtimePlatform == .macOS
            && !refreshingAccountIDs.contains(id)
            && (isManualRefreshing || !remoteUsageRefreshingAccountIDs.contains(id))
    }

    func isUsageRefreshActive(forAccountID id: String) -> Bool {
        (!isManualRefreshing && remoteUsageRefreshingAccountIDs.contains(id))
            || refreshingAccountIDs.contains(id)
    }

    func handlePageAction(_ intent: AccountsPageActionIntent) async {
        switch intent {
        case .importCurrentAuth:
            await importCurrentAuth()
        case .importAuthFile:
            guard let url = chooseAuthDocumentURL?() else { return }
            await importAuthDocument(from: url, setAsCurrent: false)
        case .addAccount:
            await addAccountViaLogin()
        case .cancelAddAccount:
            cancelAddAccount()
        case .toggleUsageProgressDisplay:
            await toggleUsageProgressDisplay()
        case .smartSwitch:
            await smartSwitch()
        case .refreshUsage:
            await refreshUsage()
        case .toggleCollapse:
            toggleAllAccountsCollapsed()
        }
    }

    // MARK: - Auth Mode

    func loadAPIKeyProfiles() async {
        do {
            let mode = try await coordinator.activeAuthMode()
            let profiles = try await coordinator.listAPIKeyProfiles()
            activeAuthMode = mode
            apiKeyProfiles = profiles
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func setActiveAuthMode(_ mode: ActiveAuthMode) {
        activeAuthMode = mode
    }

    // MARK: - API Key Profile CRUD

    func beginAddAPIKeyProfile() {
        editingAPIKeyProfile = nil
        isEditingAPIKeyProfile = true
    }

    func beginEditAPIKeyProfile(_ profile: APIKeyProfile) {
        editingAPIKeyProfile = profile
        isEditingAPIKeyProfile = true
    }

    func saveAPIKeyProfile(_ profile: APIKeyProfile) async {
        do {
            if editingAPIKeyProfile != nil {
                _ = try await coordinator.updateAPIKeyProfile(profile)
            } else {
                _ = try await coordinator.addAPIKeyProfile(profile)
            }
            isEditingAPIKeyProfile = false
            editingAPIKeyProfile = nil
            await loadAPIKeyProfiles()
            notice = NoticeMessage(style: .success, text: L10n.tr("apikey.notice.saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteAPIKeyProfile(id: String) async {
        do {
            try await coordinator.deleteAPIKeyProfile(id: id)
            await loadAPIKeyProfiles()
            notice = NoticeMessage(style: .success, text: L10n.tr("apikey.notice.deleted"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func switchToAPIKeyProfile(id: String) async {
        switchingAPIKeyProfileID = id
        do {
            let result = try await coordinator.switchToAPIKeyProfile(id: id)
            await loadAPIKeyProfiles()
            let message = result.usedFallbackCLI
                ? L10n.tr("apikey.notice.switched_fallback")
                : L10n.tr("apikey.notice.switched")
            notice = NoticeMessage(style: .success, text: message)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
        switchingAPIKeyProfileID = nil
    }

    func switchToChatGPTAccount(id: String) async {
        switchingAccountID = id
        defer { switchingAccountID = nil }

        do {
            let result = try await coordinator.switchToChatGPTAccount(id: id)
            await loadAPIKeyProfiles()
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishAndSyncLocalAccountsMutation(accounts)
            if let selectedAccount = accounts.first(where: { $0.id == id }) {
                syncCurrentAccountSelectionInBackground(accountID: selectedAccount.accountID)
            }
            notice = buildSwitchNotice(execution: result)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
