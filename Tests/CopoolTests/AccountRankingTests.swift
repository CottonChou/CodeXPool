import XCTest
@testable import Copool

final class AccountRankingTests: XCTestCase {
    func testPickBestAccountChoosesMostRemainingQuota() {
        let best = makeAccount(id: "a", weekUsed: 15, hourUsed: 30)
        let medium = makeAccount(id: "b", weekUsed: 40, hourUsed: 30)
        let worst = makeAccount(id: "c", weekUsed: 80, hourUsed: 90)

        let picked = AccountRanking.pickBestAccount([worst, medium, best])

        XCTAssertEqual(picked?.id, best.id)
    }

    private func makeAccount(id: String, weekUsed: Double, hourUsed: Double) -> AccountSummary {
        AccountSummary(
            id: id,
            label: id,
            email: nil,
            accountID: id,
            planType: nil,
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: UsageSnapshot(
                fetchedAt: 0,
                planType: nil,
                fiveHour: UsageWindow(usedPercent: hourUsed, windowSeconds: 5 * 60 * 60, resetAt: nil),
                oneWeek: UsageWindow(usedPercent: weekUsed, windowSeconds: 7 * 24 * 60 * 60, resetAt: nil),
                credits: nil
            ),
            usageError: nil,
            isCurrent: false
        )
    }
}
