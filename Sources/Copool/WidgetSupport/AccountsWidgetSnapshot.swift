import Foundation

enum AccountsWidgetConfiguration {
    static let kind = "CopoolAccountsWidget"
    static let appGroupIdentifier = "group.com.alick.copool"
    static let snapshotFilename = "accounts-widget-snapshot.json"
}

struct AccountsWidgetSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Int64
    var currentCard: AccountsWidgetCardSnapshot?
    var secondaryCard: AccountsWidgetCardSnapshot?
    var rows: [AccountsWidgetRowSnapshot]

    static let empty = AccountsWidgetSnapshot(
        generatedAt: 0,
        currentCard: nil,
        secondaryCard: nil,
        rows: []
    )
}

struct AccountsWidgetCardSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var planLabel: String
    var workspaceLabel: String?
    var accountLabel: String
    var fiveHour: AccountsWidgetWindowSnapshot
    var oneWeek: AccountsWidgetWindowSnapshot
}

struct AccountsWidgetWindowSnapshot: Codable, Equatable, Sendable {
    var title: String
    var progressFraction: Double
    var usedText: String
    var remainingText: String
    var resetText: String
}

struct AccountsWidgetRowSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var planLabel: String
    var workspaceOrAccountLabel: String
    var accountLabel: String?
    var fiveHourRemainingText: String
    var oneWeekRemainingText: String
    var fiveHourResetText: String
    var oneWeekResetText: String
}
