import CoreGraphics

/// Centralized layout inputs to avoid duplicated sizing logic across pages.
enum LayoutRules {
    static let pagePadding = CGFloat(16)
    static let sectionSpacing = CGFloat(16)
    static let cardRadius = CGFloat(14)
    static let listRowSpacing = CGFloat(10)
    static let minimumPanelWidth = CGFloat(380)
    static let minimumPanelHeight = CGFloat(370)
    static let defaultPanelWidth = CGFloat(400)
    static let defaultPanelHeight = CGFloat(400)
    static let tabSwitcherMaxWidth = CGFloat(260)
    static let accountsRowSpacing = CGFloat(10)
    static let accountsCardWidth = CGFloat(280)
    static let proxyDetailCardSpacing = CGFloat(12)
}
