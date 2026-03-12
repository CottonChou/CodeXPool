import Foundation

enum AppLocale: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }
    var identifier: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .english:
            return "language.english"
        case .simplifiedChinese:
            return "language.simplified_chinese"
        case .japanese:
            return "language.japanese"
        case .korean:
            return "language.korean"
        }
    }

    static func resolve(_ value: String) -> AppLocale {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.hasPrefix("zh") { return .simplifiedChinese }
        if normalized.hasPrefix("ja") { return .japanese }
        if normalized.hasPrefix("ko") { return .korean }
        return .english
    }
}
