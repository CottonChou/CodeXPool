import Foundation

struct AccountsWidgetSnapshotStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> AccountsWidgetSnapshot {
        guard let url = snapshotURL else {
            return .empty
        }

        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(AccountsWidgetSnapshot.self, from: data) else {
            return .empty
        }

        return snapshot
    }

    @discardableResult
    func save(_ snapshot: AccountsWidgetSnapshot) throws -> Bool {
        guard let url = snapshotURL else {
            return false
        }

        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
        return true
    }

    private var snapshotURL: URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: AccountsWidgetConfiguration.appGroupIdentifier)?
            .appendingPathComponent(AccountsWidgetConfiguration.snapshotFilename, isDirectory: false)
    }
}
