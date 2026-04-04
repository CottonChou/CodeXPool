import Foundation
import Combine

@MainActor
enum AccountsDebugTrace {
    private static let environmentKey = "COPOOL_TRACE_INVALIDATION"
    private static var didPrepareLogFile = false

    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment[environmentKey] == "1"
#else
        false
#endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let uptime = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let line = "[AccountsTrace \(uptime)] \(message())"
        prepareLogFileIfNeeded()
        append(line)
        print(line)
    }

    private static var logFileURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("accounts-trace.log")
    }

    private static func prepareLogFileIfNeeded() {
        guard !didPrepareLogFile, let logFileURL else { return }
        didPrepareLogFile = true
        try? FileManager.default.removeItem(at: logFileURL)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }

    private static func append(_ line: String) {
        guard
            let data = "\(line)\n".data(using: .utf8),
            let logFileURL
        else { return }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }

        try? data.write(to: logFileURL)
    }
}

private func makeDependencyPublisher<Value: Equatable>(
    _ publisher: Published<Value>.Publisher
) -> AnyPublisher<Value, Never> {
    publisher
        .removeDuplicates()
        .dropFirst()
        .eraseToAnyPublisher()
}

private func makeVoidDependencyPublisher<Value: Equatable>(
    _ publisher: Published<Value>.Publisher
) -> AnyPublisher<Void, Never> {
    makeDependencyPublisher(publisher)
        .map { _ in () }
        .eraseToAnyPublisher()
}

private func makeChangePublisher<Value: Equatable>(
    _ publisher: Published<Value>.Publisher
) -> AnyPublisher<(previous: Value, current: Value), Never> {
    publisher
        .removeDuplicates()
        .scan([Value]()) { values, value in
            Array((values + [value]).suffix(2))
        }
        .compactMap { values in
            guard values.count == 2 else { return nil }
            return (previous: values[0], current: values[1])
        }
        .eraseToAnyPublisher()
}

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

    private struct CardStoreSyncStats {
        let total: Int
        let inserted: Int
        let updated: Int
        let removed: Int
    }

    struct DebugRefreshEvent: Equatable {
        enum Kind: Equatable {
            case full
            case content
            case allCards
            case scopedCards(Int)
        }

        let kind: Kind
        let trigger: String
        let total: Int?
        let updated: Int
        let inserted: Int
        let removed: Int
        let contentChanged: Bool?
    }

#if DEBUG
    private(set) var debugRefreshEvents: [DebugRefreshEvent] = []
#endif

    private let model: AccountsPageModel
    private var cancellables: Set<AnyCancellable> = []
    private var cardStoresByID: [String: AccountCardStore] = [:]

    init(model: AccountsPageModel) {
        self.model = model
        contentPresentation = model.makeContentPresentation()
        _ = syncCardStores(with: model.makeAccountCardViewStates())
        bind()
    }

    private func bind() {
        makeDependencyPublisher(model.$state)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAllPresentations(trigger: "state")
                }
            }
            .store(in: &cancellables)

        makeChangePublisher(model.$collapsedAccountIDs)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    let changedAccountIDs = change.previous.symmetricDifference(change.current)
                    self?.refreshContentPresentation(trigger: "collapsedAccountIDs")
                    self?.refreshCardPresentations(
                        forAccountIDs: changedAccountIDs,
                        trigger: "collapsedAccountIDs"
                    )
                }
            }
            .store(in: &cancellables)

        makeChangePublisher(model.$switchingAccountID)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    self?.refreshCardPresentations(
                        forAccountIDs: Set([change.previous, change.current].compactMap { $0 }),
                        trigger: "switchingAccountID"
                    )
                }
            }
            .store(in: &cancellables)

        makeChangePublisher(model.$refreshingAccountIDs)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    self?.refreshCardPresentations(
                        forAccountIDs: change.previous.symmetricDifference(change.current),
                        trigger: "refreshingAccountIDs"
                    )
                }
            }
            .store(in: &cancellables)

        makeChangePublisher(model.$remoteUsageRefreshingAccountIDs)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    self?.refreshCardPresentations(
                        forAccountIDs: change.previous.symmetricDifference(change.current),
                        trigger: "remoteUsageRefreshingAccountIDs"
                    )
                }
            }
            .store(in: &cancellables)

        makeDependencyPublisher(model.$usageProgressDisplayMode)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAllCardPresentations(trigger: "usageProgressDisplayMode")
                }
            }
            .store(in: &cancellables)

        makeDependencyPublisher(model.$pendingWorkspaceAuthorizations)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshContentPresentation(trigger: "pendingWorkspaceAuthorizations")
                }
            }
            .store(in: &cancellables)

        makeDependencyPublisher(model.$pendingWorkspaceAuthorizationError)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshContentPresentation(trigger: "pendingWorkspaceAuthorizationError")
                }
            }
            .store(in: &cancellables)

        makeDependencyPublisher(model.$authorizingWorkspaceID)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshContentPresentation(trigger: "authorizingWorkspaceID")
                }
            }
            .store(in: &cancellables)
    }

    func cardStore(for id: String) -> AccountCardStore? {
        cardStoresByID[id]
    }

    private func refreshAllPresentations(trigger: String) {
        let syncStats = syncCardStores(with: model.makeAccountCardViewStates())
        refreshContentPresentation(trigger: trigger)
        recordDebugRefreshEvent(
            kind: .full,
            trigger: trigger,
            total: syncStats.total,
            updated: syncStats.updated,
            inserted: syncStats.inserted,
            removed: syncStats.removed,
            contentChanged: nil
        )
        AccountsDebugTrace.log(
            "full refresh trigger=\(trigger) cards=\(syncStats.total) updated=\(syncStats.updated) inserted=\(syncStats.inserted) removed=\(syncStats.removed)"
        )
    }

    private func refreshContentPresentation(trigger: String = "manual") {
        let nextContent = model.makeContentPresentation()
        let contentChanged = contentPresentation != nextContent
        if contentChanged {
            contentPresentation = nextContent
        }

        recordDebugRefreshEvent(
            kind: .content,
            trigger: trigger,
            total: nil,
            updated: 0,
            inserted: 0,
            removed: 0,
            contentChanged: contentChanged
        )
        AccountsDebugTrace.log(
            "content refresh trigger=\(trigger) contentChanged=\(contentChanged ? "yes" : "no")"
        )
    }

    private func refreshAllCardPresentations(trigger: String) {
        let syncStats = syncCardStores(with: model.makeAccountCardViewStates())
        recordDebugRefreshEvent(
            kind: .allCards,
            trigger: trigger,
            total: syncStats.total,
            updated: syncStats.updated,
            inserted: syncStats.inserted,
            removed: syncStats.removed,
            contentChanged: nil
        )
        AccountsDebugTrace.log(
            "card refresh trigger=\(trigger) scope=all cards=\(syncStats.total) updated=\(syncStats.updated) inserted=\(syncStats.inserted) removed=\(syncStats.removed)"
        )
    }

    private func refreshCardPresentations(
        forAccountIDs accountIDs: Set<String>,
        trigger: String
    ) {
        guard !accountIDs.isEmpty else { return }
        let syncStats = syncCardStores(forAccountIDs: accountIDs)
        recordDebugRefreshEvent(
            kind: .scopedCards(accountIDs.count),
            trigger: trigger,
            total: syncStats.total,
            updated: syncStats.updated,
            inserted: syncStats.inserted,
            removed: syncStats.removed,
            contentChanged: nil
        )
        AccountsDebugTrace.log(
            "card refresh trigger=\(trigger) scope=\(accountIDs.count) updated=\(syncStats.updated) inserted=\(syncStats.inserted) removed=\(syncStats.removed)"
        )
    }

    private func syncCardStores(with presentations: [AccountCardViewState]) -> CardStoreSyncStats {
        let previousIDs = Set(cardStoresByID.keys)
        let nextIDs = Set(presentations.map(\.id))
        let removed = previousIDs.subtracting(nextIDs).count
        cardStoresByID = cardStoresByID.filter { nextIDs.contains($0.key) }
        var inserted = 0
        var updated = 0

        for presentation in presentations {
            if let existingStore = cardStoresByID[presentation.id] {
                if existingStore.presentation != presentation {
                    updated += 1
                }
                existingStore.update(presentation)
            } else {
                cardStoresByID[presentation.id] = AccountCardStore(presentation: presentation)
                inserted += 1
            }
        }

        return CardStoreSyncStats(
            total: presentations.count,
            inserted: inserted,
            updated: updated,
            removed: removed
        )
    }

    private func syncCardStores(forAccountIDs accountIDs: Set<String>) -> CardStoreSyncStats {
        var inserted = 0
        var updated = 0
        var removed = 0

        for accountID in accountIDs {
            let nextPresentation = model.makeAccountCardViewState(forAccountID: accountID)
            let existingStore = cardStoresByID[accountID]

            switch (existingStore, nextPresentation) {
            case let (.some(store), .some(presentation)):
                if store.presentation != presentation {
                    updated += 1
                }
                store.update(presentation)
            case (.none, .some(let presentation)):
                cardStoresByID[accountID] = AccountCardStore(presentation: presentation)
                inserted += 1
            case (.some, .none):
                cardStoresByID.removeValue(forKey: accountID)
                removed += 1
            case (.none, .none):
                continue
            }
        }

        return CardStoreSyncStats(
            total: cardStoresByID.count,
            inserted: inserted,
            updated: updated,
            removed: removed
        )
    }

    private func recordDebugRefreshEvent(
        kind: DebugRefreshEvent.Kind,
        trigger: String,
        total: Int?,
        updated: Int,
        inserted: Int,
        removed: Int,
        contentChanged: Bool?
    ) {
#if DEBUG
        debugRefreshEvents.append(
            DebugRefreshEvent(
                kind: kind,
                trigger: trigger,
                total: total,
                updated: updated,
                inserted: inserted,
                removed: removed,
                contentChanged: contentChanged
            )
        )
#else
        _ = kind
        _ = trigger
        _ = total
        _ = updated
        _ = inserted
        _ = removed
        _ = contentChanged
#endif
    }
}

@MainActor
final class AccountsPageChromeStore: ObservableObject {
    @Published private(set) var macActionBarPresentation: AccountsActionBarPresentation
    @Published private(set) var leadingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    @Published private(set) var trailingToolbarButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]

    private let model: AccountsPageModel
    private var cancellables: Set<AnyCancellable> = []

    init(model: AccountsPageModel) {
        self.model = model
        macActionBarPresentation = model.makeMacActionBarPresentation()
        leadingToolbarButtons = model.leadingToolbarButtons
        trailingToolbarButtons = model.trailingToolbarButtons
        bind()
    }

    private func bind() {
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

    private func macActionBarDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            makeVoidDependencyPublisher(model.$state),
            makeVoidDependencyPublisher(model.$collapsedAccountIDs),
            makeVoidDependencyPublisher(model.$isImporting),
            makeVoidDependencyPublisher(model.$isAdding),
            makeVoidDependencyPublisher(model.$switchingAccountID),
            makeVoidDependencyPublisher(model.$isManualRefreshing)
        )
        .eraseToAnyPublisher()
    }

    private func leadingToolbarDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            makeVoidDependencyPublisher(model.$isImporting),
            makeVoidDependencyPublisher(model.$isAdding)
        )
        .eraseToAnyPublisher()
    }

    private func trailingToolbarDependenciesPublisher() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            makeVoidDependencyPublisher(model.$state),
            makeVoidDependencyPublisher(model.$collapsedAccountIDs),
            makeVoidDependencyPublisher(model.$isAdding),
            makeVoidDependencyPublisher(model.$isManualRefreshing)
        )
        .eraseToAnyPublisher()
    }
}
