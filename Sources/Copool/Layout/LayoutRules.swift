import CoreGraphics

/// Centralized layout inputs to avoid duplicated sizing logic across pages.
enum LayoutRules {
    static let pagePadding = CGFloat(16)
    static let sectionSpacing = CGFloat(16)
    static let cardRadius = CGFloat(14)
    static let listRowSpacing = CGFloat(10)
    static let tabSwitcherMaxWidth = CGFloat(260)
    static let minimumPanelHeight = CGFloat(520)
    static let defaultPanelHeight = CGFloat(620)
    static let accountsRowSpacing = CGFloat(10)
    static let accountsExpandedColumns = 2
    static let accountsCollapsedColumns = 3
    static let accountsCardWidth = CGFloat(250)
    static let proxyDetailCardSpacing = CGFloat(12)
    static let proxyHeroPortFieldWidth = CGFloat(108)
    static let proxyRemoteFieldMinWidth = CGFloat(160)
    static let proxyRemoteActionMinWidth = CGFloat(118)
    static let proxyRemoteMetricMinWidth = CGFloat(108)
    static let proxyRemoteMetricHeight = CGFloat(68)
    static let proxyRemoteDetailMinWidth = CGFloat(220)
    static let proxyRemoteLogsHeight = CGFloat(120)
    static let proxyPublicModeMinWidth = CGFloat(240)
    static let proxyPublicFieldMinWidth = CGFloat(220)
    static let proxyPublicStatusCardMinWidth = CGFloat(170)

    static var accountsTwoColumnContentWidth: CGFloat {
        accountsCardWidth * CGFloat(accountsExpandedColumns) + accountsRowSpacing
    }

    static var accountsPageTargetWidth: CGFloat {
        accountsTwoColumnContentWidth + pagePadding * 2
    }

    static var accountsCollapsedCardWidth: CGFloat {
        (accountsPageTargetWidth - pagePadding * 2 - accountsRowSpacing * 2) / CGFloat(accountsCollapsedColumns)
    }

    static var minimumPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static var defaultPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static var maximumPanelWidth: CGFloat {
        accountsPageTargetWidth
    }
}
