import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        #if os(macOS)
        MacSettingsPageContent(model: model)
        #else
        IOSSettingsPageContent(model: model)
        #endif
    }
}

#if os(macOS)
private struct MacSettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SettingsGeneralSection(model: model)
                SettingsLanguageSection(model: model)
                SettingsSwitchBehaviorSection(model: model)
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)

            SettingsQuitFooter()
        }
        .task {
            await model.loadIfNeeded()
        }
    }
}

private struct SettingsGeneralSection: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        Section("settings.section.general") {
            Toggle("settings.launch_at_startup", isOn: Binding(
                get: { model.settings.launchAtStartup },
                set: { model.setLaunchAtStartup($0) }
            ))
            .toggleStyle(.switch)

            Toggle("settings.launch_codex_after_switch", isOn: Binding(
                get: { model.settings.launchCodexAfterSwitch },
                set: { model.setLaunchAfterSwitch($0) }
            ))
            .toggleStyle(.switch)

            Toggle("settings.auto_start_api_proxy", isOn: Binding(
                get: { model.settings.autoStartApiProxy },
                set: { model.setAutoStartProxy($0) }
            ))
            .toggleStyle(.switch)

            Toggle("settings.local_proxy_host_api_only", isOn: Binding(
                get: { model.settings.localProxyHostAPIOnly },
                set: { model.setLocalProxyHostAPIOnly($0) }
            ))
            .toggleStyle(.switch)
        }
    }
}

private struct SettingsSwitchBehaviorSection: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        Section("settings.section.switch_behavior") {
            Toggle("settings.auto_smart_switch", isOn: Binding(
                get: { model.settings.autoSmartSwitch },
                set: { model.setAutoSmartSwitch($0) }
            ))
            .toggleStyle(.switch)

            Toggle("settings.sync_opencode_openai_auth", isOn: Binding(
                get: { model.settings.syncOpencodeOpenaiAuth },
                set: { model.setSyncOpencodeOpenaiAuth($0) }
            ))
            .toggleStyle(.switch)

            Toggle("settings.restart_editors_on_switch", isOn: Binding(
                get: { model.settings.restartEditorsOnSwitch },
                set: { model.setRestartEditorsOnSwitch($0) }
            ))
            .toggleStyle(.switch)

            Picker("settings.editor_restart_target", selection: Binding(
                get: { model.settings.restartEditorTargets.first },
                set: { model.setRestartEditorTarget($0) }
            )) {
                Text("common.none").tag(EditorAppID?.none)
                ForEach(model.installedEditorApps) { app in
                    Text(app.label).tag(EditorAppID?.some(app.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.settings.restartEditorsOnSwitch || model.installedEditorApps.isEmpty)
        }
    }
}

private struct SettingsQuitFooter: View {
    var body: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            Spacer(minLength: 0)

            Button(role: .destructive) {
                quitApp()
            } label: {
                Text("common.quit")
            }
            .buttonStyle(.frostedCapsule(prominent: true, tint: .red))
        }
        .padding(.horizontal, LayoutRules.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func quitApp() {
        #if canImport(AppKit)
        NSApp.terminate(nil)
        #endif
    }
}
#endif

private struct IOSSettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        Form {
            SettingsLanguageSection(model: model)
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .task {
            await model.loadIfNeeded()
        }
    }
}

private struct SettingsLanguageSection: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        Section("settings.section.language") {
            Picker("settings.language", selection: Binding(
                get: { AppLocale.resolve(model.settings.locale) },
                set: { model.setLocale($0.identifier) }
            )) {
                ForEach(AppLocale.allCases) { locale in
                    Text(L10n.tr(locale.displayNameKey)).tag(locale)
                }
            }
            .pickerStyle(.menu)
        }
    }
}
