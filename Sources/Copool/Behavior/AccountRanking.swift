import Foundation

enum AccountRanking {
    static func remainingScore(for account: AccountSummary) -> Double {
        let oneWeekUsed = account.usage?.oneWeek?.usedPercent ?? 100
        let fiveHourUsed = account.usage?.fiveHour?.usedPercent ?? 100

        let oneWeekRemaining = max(0, 100 - oneWeekUsed)
        let fiveHourRemaining = max(0, 100 - fiveHourUsed)

        return oneWeekRemaining * 0.7 + fiveHourRemaining * 0.3
    }

    static func sortByRemaining(_ accounts: [AccountSummary]) -> [AccountSummary] {
        accounts.sorted { left, right in
            remainingScore(for: left) > remainingScore(for: right)
        }
    }

    static func pickBestAccount(_ accounts: [AccountSummary]) -> AccountSummary? {
        sortByRemaining(accounts).first
    }
}
