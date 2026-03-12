import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct RootScene: View {
    @State private var selectedTab: AppTab = .accounts
    @StateObject private var accountsModel: AccountsPageModel
    @StateObject private var proxyModel: ProxyPageModel
    @StateObject private var settingsModel: SettingsPageModel

    init(container: AppContainer) {
        _accountsModel = StateObject(wrappedValue: container.accountsModel)
        _proxyModel = StateObject(wrappedValue: container.proxyModel)
        _settingsModel = StateObject(wrappedValue: container.settingsModel)
    }

    private var runtimeLocale: Locale {
        Locale(identifier: AppLocale.resolve(settingsModel.settings.locale).identifier)
    }

    private var currentNotice: NoticeMessage? {
        switch selectedTab {
        case .accounts:
            return accountsModel.notice
        case .proxy:
            return proxyModel.notice
        case .settings:
            return settingsModel.notice
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTabBar(selection: $selectedTab)
            .frame(maxWidth: LayoutRules.tabSwitcherMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, LayoutRules.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Group {
                switch selectedTab {
                case .accounts:
                    AccountsPageView(model: accountsModel)
                case .proxy:
                    ProxyPageView(model: proxyModel)
                case .settings:
                    SettingsPageView(model: settingsModel)
                }
            }
        }
        .environment(\.locale, runtimeLocale)
        .onAppear {
            L10n.setLocale(identifier: settingsModel.settings.locale)
        }
        .onChange(of: settingsModel.settings.locale) { _, value in
            L10n.setLocale(identifier: value)
        }
        .task {
            await settingsModel.loadIfNeeded()
            await proxyModel.bootstrapOnAppLaunch(using: settingsModel.settings)
        }
        .overlay(alignment: .top) {
            NoticeBanner(notice: currentNotice)
                .padding(.horizontal, LayoutRules.pagePadding)
                .padding(.top, 6)
                .allowsHitTesting(false)
                .zIndex(10)
        }
        .frame(minWidth: LayoutRules.minimumPanelWidth, minHeight: LayoutRules.minimumPanelHeight)
    }
}

private struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.iconName)
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(.regularMaterial)
                            .overlay {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.14))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(borderColor.opacity(0.9), lineWidth: 1)
                            }
                    }
                }
                .contentShape(Capsule())
                .accessibilityLabel(Text(tab.titleKey))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var borderColor: Color {
        #if canImport(AppKit)
        Color(nsColor: .separatorColor)
        #else
        Color.secondary.opacity(0.2)
        #endif
    }
}

private extension AppTab {
    var iconName: String {
        switch self {
        case .accounts: return "person.2"
        case .proxy: return "network"
        case .settings: return "gearshape"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .accounts: return "tab.accounts"
        case .proxy: return "tab.proxy"
        case .settings: return "tab.settings"
        }
    }
}
