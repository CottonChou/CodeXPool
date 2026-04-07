import Foundation

enum UsageProgressDisplayMode: String, Codable, Equatable, CaseIterable, Sendable {
    case used
    case remaining

    var localizationKey: String {
        switch self {
        case .used:
            return "settings.usage_progress_display.used"
        case .remaining:
            return "settings.usage_progress_display.remaining"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtStartup: Bool
    var launchCodexAfterSwitch: Bool
    var autoSmartSwitch: Bool
    var syncOpencodeOpenaiAuth: Bool
    var restartEditorsOnSwitch: Bool
    var restartEditorTargets: [EditorAppID]
    var usageProgressDisplayMode: UsageProgressDisplayMode
    var locale: String

    enum CodingKeys: String, CodingKey {
        case launchAtStartup
        case launchCodexAfterSwitch
        case autoSmartSwitch
        case syncOpencodeOpenaiAuth
        case restartEditorsOnSwitch
        case restartEditorTargets
        case usageProgressDisplayMode
        case locale
    }

    init(
        launchAtStartup: Bool,
        launchCodexAfterSwitch: Bool,
        autoSmartSwitch: Bool,
        syncOpencodeOpenaiAuth: Bool,
        restartEditorsOnSwitch: Bool,
        restartEditorTargets: [EditorAppID],
        usageProgressDisplayMode: UsageProgressDisplayMode = .used,
        locale: String
    ) {
        self.launchAtStartup = launchAtStartup
        self.launchCodexAfterSwitch = launchCodexAfterSwitch
        self.autoSmartSwitch = autoSmartSwitch
        self.syncOpencodeOpenaiAuth = syncOpencodeOpenaiAuth
        self.restartEditorsOnSwitch = restartEditorsOnSwitch
        self.restartEditorTargets = restartEditorTargets
        self.usageProgressDisplayMode = usageProgressDisplayMode
        self.locale = AppLocale.resolve(locale).identifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtStartup = try container.decodeIfPresent(Bool.self, forKey: .launchAtStartup) ?? false
        launchCodexAfterSwitch = try container.decodeIfPresent(Bool.self, forKey: .launchCodexAfterSwitch) ?? true
        autoSmartSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoSmartSwitch) ?? false
        syncOpencodeOpenaiAuth = try container.decodeIfPresent(Bool.self, forKey: .syncOpencodeOpenaiAuth) ?? false
        restartEditorsOnSwitch = try container.decodeIfPresent(Bool.self, forKey: .restartEditorsOnSwitch) ?? false
        restartEditorTargets = try container.decodeIfPresent([EditorAppID].self, forKey: .restartEditorTargets) ?? []
        usageProgressDisplayMode = try container.decodeIfPresent(
            UsageProgressDisplayMode.self,
            forKey: .usageProgressDisplayMode
        ) ?? .used
        locale = AppLocale.resolve(try container.decodeIfPresent(String.self, forKey: .locale) ?? AppLocale.systemDefault.identifier).identifier
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(launchCodexAfterSwitch, forKey: .launchCodexAfterSwitch)
        try container.encode(autoSmartSwitch, forKey: .autoSmartSwitch)
        try container.encode(syncOpencodeOpenaiAuth, forKey: .syncOpencodeOpenaiAuth)
        try container.encode(restartEditorsOnSwitch, forKey: .restartEditorsOnSwitch)
        try container.encode(restartEditorTargets, forKey: .restartEditorTargets)
        try container.encode(usageProgressDisplayMode, forKey: .usageProgressDisplayMode)
        try container.encode(locale, forKey: .locale)
    }

    static var defaultValue: AppSettings {
        AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            autoSmartSwitch: false,
            syncOpencodeOpenaiAuth: false,
            restartEditorsOnSwitch: false,
            restartEditorTargets: [],
            usageProgressDisplayMode: .used,
            locale: AppLocale.systemDefault.identifier
        )
    }
}

struct AppSettingsPatch {
    var launchAtStartup: Bool? = nil
    var launchCodexAfterSwitch: Bool? = nil
    var autoSmartSwitch: Bool? = nil
    var syncOpencodeOpenaiAuth: Bool? = nil
    var restartEditorsOnSwitch: Bool? = nil
    var restartEditorTargets: [EditorAppID]? = nil
    var usageProgressDisplayMode: UsageProgressDisplayMode? = nil
    var locale: String? = nil
}
