import XCTest
@testable import Copool

final class AppLocaleTests: XCTestCase {
    func testResolveNormalizesLegacyIdentifiers() {
        XCTAssertEqual(AppLocale.resolve("en-US"), .english)
        XCTAssertEqual(AppLocale.resolve("zh-CN"), .simplifiedChinese)
        XCTAssertEqual(AppLocale.resolve("ja-JP"), .japanese)
        XCTAssertEqual(AppLocale.resolve("ko-KR"), .korean)
    }

    func testResolveFallsBackToEnglish() {
        XCTAssertEqual(AppLocale.resolve("fr-FR"), .english)
        XCTAssertEqual(AppLocale.resolve(""), .english)
    }
}
