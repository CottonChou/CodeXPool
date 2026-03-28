import Foundation
import Combine

@MainActor
final class AccountCardStore: ObservableObject {
    @Published private(set) var presentation: AccountCardViewState

    init(presentation: AccountCardViewState) {
        self.presentation = presentation
    }
    func update(_ presentation: AccountCardViewState) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation
    }
}

@MainActor
final class AccountsPageViewStore: ObservableObject {
    @Published private(set) var contentPresentation: AccountsPageContentPresentation
    @Published private(set) var macActionBarPresentation: AccountsActionBarPresentation
    @Published private(set) var leadingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    @Published private(set) var trailingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]

    private let model: AccountsPageModel
    private var cancellables: Set<AnyCancellable> = []
    private var cardStoresByID: [String: AccountCardStore] = [:]

    init(model: AccountsPageModel) {
        self.model = model
        contentPresentation = model.makeContentPresentation()
        macActionBarPresentation = model.makeMacActionBarPresentation()
        leadingToolbarButtons = model.leadingToolbarButtons
        trailingToolbarButtons = model.trailingToolbarButtons
        syncCardStores(with: model.makeAccountCardViewStates())
        bind()
    }

    private func bind() {
        contentDependenciesPublisher()
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshContentPresentation()
                }
            }
            .store(in: &cancellables)

        macActionBarDependenciesPublisher()
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshMacActionBarPresentation()
                }
            }
            .store(in: &cancellables)

        leadingToolbarDependenciesPublisher()
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshLeadingToolbarButtons()
                }
            }
            .store(in: &cancellables)

        trailingToolbarDependenciesPublisher()
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshTrailingToolbarButtons()
                }
            }
            .store(in: &cancellables)
    }

    func syncFromModel() {
        refreshContentPresentation()
        refreshMacActionBarPresentation()
        refreshLeadingToolbarButtons()
        refreshTrailingToolbarButtons()
    }

    func cardStore(for id: String) -> AccountCardStore? {
        cardStoresByID[id]
    }

    private func refreshContentPresentation() {
        syncCardStores(with: model.makeAccountCardViewStates())

        let nextContent = model.makeContentPresentation()
        if contentPresentation != nextContent {
            contentPresentation = nextContent
        }
    }

    private func refreshMacActionBarPresentation() {
        let nextMacActionBar = model.makeMacActionBarPresentation()
        if macActionBarPresentation != nextMacActionBar {
            macActionBarPresentation = nextMacActionBar
        }
    }

    private func refreshLeadingToolbarButtons() {
        let nextLeading = model.leadingToolbarButtons
        if leadingToolbarButtons != nextLeading {
            leadingToolbarButtons = nextLeading
        }
    }

    private func refreshTrailingToolbarButtons() {
        let nextTrailing = model.trailingToolbarButtons
        if trailingToolbarButtons != nextTrailing {
            trailingToolbarButtons = nextTrailing
        }
    }

    private func syncCardStores(with presentations: [AccountCardViewState]) {
        let nextIDs = Set(presentations.map(\.id))
        cardStoresByID = cardStoresByID.filter { nextIDs.contains($0.key) }

        for presentation in presentations {
            if let existingStore = cardStoresByID[presentation.id] {
                existingStore.update(presentation)
            } else {
                cardStoresByID[presentation.id] = AccountCardStore(presentation: presentation)
            }
        }
    }

    private func contentDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            dependencyPublisher(model.$state),
            dependencyPublisher(model.$collapsedAccountIDs),
            dependencyPublisher(model.$switchingAccountID),
            dependencyPublisher(model.$refreshingAccountIDs),
            dependencyPublisher(model.$isManualRefreshing),
            dependencyPublisher(model.$isRemoteUsageRefreshing),
            dependencyPublisher(model.$usageProgressDisplayMode),
            dependencyPublisher(model.$pendingWorkspaceAuthorizations),
            dependencyPublisher(model.$pendingWorkspaceAuthorizationError),
            dependencyPublisher(model.$authorizingWorkspaceID)
        )
        .eraseToAnyPublisher()
    }

    private func macActionBarDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            dependencyPublisher(model.$state),
            dependencyPublisher(model.$collapsedAccountIDs),
            dependencyPublisher(model.$isImporting),
            dependencyPublisher(model.$isAdding),
            dependencyPublisher(model.$switchingAccountID),
            dependencyPublisher(model.$isManualRefreshing)
        )
        .eraseToAnyPublisher()
    }

    private func leadingToolbarDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            dependencyPublisher(model.$isImporting),
            dependencyPublisher(model.$isAdding)
        )
        .eraseToAnyPublisher()
    }

    private func trailingToolbarDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            dependencyPublisher(model.$state),
            dependencyPublisher(model.$collapsedAccountIDs),
            dependencyPublisher(model.$isAdding),
            dependencyPublisher(model.$isManualRefreshing)
        )
        .eraseToAnyPublisher()
    }

    private func dependencyPublisher<Value: Equatable>(
        _ publisher: Published<Value>.Publisher
    ) -> AnyPublisher<Void, Never> {
        publisher
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
