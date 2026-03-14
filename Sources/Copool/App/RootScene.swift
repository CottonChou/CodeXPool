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
        .onChange(of: selectedTab) { _, tab in
            if tab == .proxy {
                proxyModel.collapseForTabEntry()
            }
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
        .background {
            WindowSizeEnforcer(
                minWidth: LayoutRules.minimumPanelWidth,
                maxWidth: LayoutRules.maximumPanelWidth,
                minHeight: LayoutRules.minimumPanelHeight,
                idealHeight: LayoutRules.defaultPanelHeight
            )
            .frame(width: 0, height: 0)
        }
        .frame(
            minWidth: LayoutRules.minimumPanelWidth,
            idealWidth: LayoutRules.defaultPanelWidth,
            maxWidth: LayoutRules.maximumPanelWidth,
            minHeight: LayoutRules.minimumPanelHeight
        )
    }
}

#if canImport(AppKit)
private struct WindowSizeEnforcer: NSViewRepresentable {
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let minHeight: CGFloat
    let idealHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            apply(on: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(on: nsView.window)
        }
    }

    private func apply(on window: NSWindow?) {
        guard let window else { return }
        window.contentMinSize = NSSize(width: minWidth, height: minHeight)
        window.contentMaxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)

        var targetSize = window.contentLayoutRect.size
        let clampedWidth = min(max(targetSize.width, minWidth), maxWidth)
        let clampedHeight = max(targetSize.height, minHeight)

        guard clampedWidth != targetSize.width || clampedHeight != targetSize.height else { return }
        targetSize.width = clampedWidth
        targetSize.height = clampedHeight > 0 ? clampedHeight : idealHeight
        window.setContentSize(targetSize)
    }
}
#else
private struct WindowSizeEnforcer: View {
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let minHeight: CGFloat
    let idealHeight: CGFloat

    var body: some View {
        EmptyView()
    }
}
#endif

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
