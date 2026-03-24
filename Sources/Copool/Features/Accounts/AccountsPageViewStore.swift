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
        model.objectWillChange
        .sink { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.refreshPresentations()
            }
        }
        .store(in: &cancellables)
    }

    func syncFromModel() {
        refreshPresentations()
    }

    func cardStore(for id: String) -> AccountCardStore? {
        cardStoresByID[id]
    }

    private func refreshPresentations() {
        syncCardStores(with: model.makeAccountCardViewStates())

        let nextContent = model.makeContentPresentation()
        if contentPresentation != nextContent {
            contentPresentation = nextContent
        }

        let nextMacActionBar = model.makeMacActionBarPresentation()
        if macActionBarPresentation != nextMacActionBar {
            macActionBarPresentation = nextMacActionBar
        }

        let nextLeading = model.leadingToolbarButtons
        if leadingToolbarButtons != nextLeading {
            leadingToolbarButtons = nextLeading
        }

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
}
