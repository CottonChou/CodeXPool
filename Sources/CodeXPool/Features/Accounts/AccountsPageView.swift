import SwiftUI
import UniformTypeIdentifiers

struct AccountsPageView: View {
    @State private var areCardsPresented = false
    @State private var didRunInitialCardEntrance = false
    @State private var isImportingAuthFile = false
    @State private var displayMode: ActiveAuthMode = .chatgpt
    @State private var isShowingAPIKeyEditor = false
    @State private var editingProfile: APIKeyProfile?
    @StateObject private var contentStore: AccountsPageViewStore
    @StateObject private var chromeStore: AccountsPageChromeStore

    let model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void

    init(
        model: AccountsPageModel,
        currentLocale: AppLocale,
        onSelectLocale: @escaping (AppLocale) -> Void
    ) {
        self.model = model
        self.currentLocale = currentLocale
        self.onSelectLocale = onSelectLocale
        _contentStore = StateObject(wrappedValue: AccountsPageViewStore(model: model))
        _chromeStore = StateObject(wrappedValue: AccountsPageChromeStore(model: model))
        let initMode = model.activeAuthMode
        _displayMode = State(initialValue: initMode)
        let hasResolvedInitialState = model.hasResolvedInitialState
        _areCardsPresented = State(initialValue: hasResolvedInitialState)
        _didRunInitialCardEntrance = State(initialValue: hasResolvedInitialState)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                AuthModeSwitcher(activeMode: $displayMode)
                    .frame(maxWidth: 240)
                    .padding(.horizontal, LayoutRules.pagePadding)
                    .padding(.vertical, 8)

                ZStack {
                    chatGPTContent
                        .opacity(displayMode == .chatgpt ? 1 : 0)
                        .allowsHitTesting(displayMode == .chatgpt)

                    APIKeyProfileListView(
                        model: model,
                        onAddProfile: {
                            editingProfile = nil
                            isShowingAPIKeyEditor = true
                        },
                        onEditProfile: { profile in
                            editingProfile = profile
                            isShowingAPIKeyEditor = true
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(displayMode == .apiKey ? 1 : 0)
                    .allowsHitTesting(displayMode == .apiKey)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isShowingAPIKeyEditor {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowingAPIKeyEditor = false
                    }

                APIKeyProfileEditorView(
                    existingProfile: editingProfile,
                    onSave: { profile in
                        isShowingAPIKeyEditor = false
                        Task { await model.saveAPIKeyProfile(profile) }
                    },
                    onCancel: {
                        isShowingAPIKeyEditor = false
                    }
                )
                .frame(width: 420, height: 520)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowingAPIKeyEditor)
        .task {
            for await mode in model.$activeAuthMode.values {
                if displayMode != mode {
                    displayMode = mode
                }
            }
        }
    }

    private var chatGPTContent: some View {
        AccountsPageShell(
            contentStore: contentStore,
            chromeStore: chromeStore,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            areCardsPresented: areCardsPresented,
            onTriggerAction: triggerAction,
            onToggleCollapse: toggleCollapse,
            onSwitchAccount: switchAccount,
            onRefreshAccountUsage: refreshUsage,
            onAuthorizeWorkspace: authorizeWorkspace,
            onCancelAuthorizeWorkspace: cancelAuthorizeWorkspace,
            onDeletePendingWorkspace: deletePendingWorkspace,
            onDeleteAccount: deleteAccount
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: $isImportingAuthFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportAuthFile(result)
        }
        .onAppear {
            triggerInitialCardEntranceIfNeeded(for: contentAccountCount)
        }
        .onChange(of: contentAccountCount) { _, newValue in
            triggerInitialCardEntranceIfNeeded(for: newValue)
        }
    }

    private var contentAccountCount: Int? {
        guard case .content(let cards) = contentStore.contentPresentation.state else { return nil }
        return cards.count
    }

    private func triggerInitialCardEntranceIfNeeded(for count: Int?) {
        guard count != nil, !didRunInitialCardEntrance else { return }
        didRunInitialCardEntrance = true
        areCardsPresented = true
    }

    private func triggerAction(_ intent: AccountsPageActionIntent) {
        #if os(iOS)
        if intent == .importAuthFile {
            isImportingAuthFile = true
            return
        }
        #endif
        Task { await model.handlePageAction(intent) }
    }

    private func handleImportAuthFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.importAuthDocument(from: url, setAsCurrent: false) }
        case .failure(let error):
            model.notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func toggleCollapse() {
        withAnimation(AccountsAnimationRules.collapseToggle) {
            model.toggleAllAccountsCollapsed()
        }
    }

    private func switchAccount(id: String) {
        if model.activeAuthMode == .apiKey {
            Task { await model.switchToChatGPTAccount(id: id) }
        } else {
            Task { await model.switchAccount(id: id) }
        }
    }

    private func refreshUsage(forAccountID id: String) {
        Task { await model.refreshUsage(forAccountID: id) }
    }

    private func deleteAccount(id: String) {
        Task { await model.deleteAccount(id: id) }
    }

    private func authorizeWorkspace(id: String) {
        Task { await model.authorizePendingWorkspace(id: id) }
    }

    private func cancelAuthorizeWorkspace() {
        model.cancelPendingWorkspaceAuthorization()
    }

    private func deletePendingWorkspace(id: String) {
        Task { await model.deletePendingWorkspace(id: id) }
    }
}
