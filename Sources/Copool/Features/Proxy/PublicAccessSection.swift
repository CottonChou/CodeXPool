import SwiftUI

struct PublicAccessSection: View {
    @ObservedObject var model: ProxyPageModel
    let onCopy: (String?) -> Void
    @State private var modeCardHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.cloudflaredExpanded {
                expandedContent
            }
        }
        .padding(16)
        .cardSurface(cornerRadius: LayoutRules.cardRadius)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.tr("proxy.section.public_access"))
                    .font(.headline)

                Spacer(minLength: 0)

                CollapseChevronButton(isExpanded: model.cloudflaredExpanded) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.cloudflaredSectionExpanded.toggle()
                    }
                }
            }

            HStack(spacing: 10) {
                Text(L10n.tr("proxy.toggle.enable_public_access"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                PublicAccessSwitchPill(
                    isOn: Binding(
                        get: { model.publicAccessEnabled },
                        set: { value in
                            Task { await model.setPublicAccessEnabled(value) }
                        }
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if !model.proxyStatus.running {
            callout(
                title: L10n.tr("proxy.public.callout.start_local_first_title"),
                message: L10n.tr("proxy.public.callout.start_local_first_message")
            )
        }

        if !model.cloudflaredStatus.installed {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("proxy.public.not_installed_label"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("proxy.public.install_title"))
                        .font(.headline)
                    Text(L10n.tr("proxy.public.install_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ProxyActionStrip(
                    buttons: [model.publicAccessInstallButton],
                    onAction: model.handlePublicAccessAction
                )
            }
            .padding(12)
            .cardSurface(cornerRadius: 12)
        } else {
            modeGrid

            if model.cloudflaredTunnelMode == .quick {
                callout(
                    title: L10n.tr("proxy.public.quick_note_title"),
                    message: L10n.tr("proxy.public.quick_note_message")
                )
            }

            if model.cloudflaredTunnelMode == .named {
                namedTunnelForm
            }

            toolbar
            statusGrid
        }
    }

    private var modeGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10)
            ],
            spacing: 10
        ) {
            PublicAccessModeCard(
                kicker: L10n.tr("proxy.public.mode.quick_kicker"),
                title: L10n.tr("proxy.public.mode.quick_title"),
                message: L10n.tr("proxy.public.mode.quick_message"),
                selected: model.cloudflaredTunnelMode == .quick
            ) {
                model.updateCloudflaredTunnelMode(.quick)
            }
            .frame(height: modeCardHeight > 0 ? modeCardHeight : nil, alignment: .top)
            .disabled(!model.canEditCloudflaredInput)

            PublicAccessModeCard(
                kicker: L10n.tr("proxy.public.mode.named_kicker"),
                title: L10n.tr("proxy.public.mode.named_title"),
                message: L10n.tr("proxy.public.mode.named_message"),
                selected: model.cloudflaredTunnelMode == .named
            ) {
                model.updateCloudflaredTunnelMode(.named)
            }
            .frame(height: modeCardHeight > 0 ? modeCardHeight : nil, alignment: .top)
            .disabled(!model.canEditCloudflaredInput)
        }
        .onPreferenceChange(PublicAccessModeCardHeightKey.self) { nextHeight in
            guard nextHeight > 0, abs(modeCardHeight - nextHeight) > 0.5 else { return }
            modeCardHeight = nextHeight
        }
    }

    private var namedTunnelForm: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyPublicFieldMinWidth), spacing: 10)],
            spacing: 10
        ) {
            ProxyFieldGroup(title: L10n.tr("proxy.public.field.api_token")) {
                SecureField(
                    L10n.tr("proxy.public.field.api_token_placeholder"),
                    text: Binding(
                        get: { model.cloudflaredNamedInput.apiToken },
                        set: { model.cloudflaredNamedInput.apiToken = $0 }
                    )
                )
                .frostedRoundedInput()
                .disabled(!model.canEditCloudflaredInput)
            }

            ProxyFieldGroup(title: L10n.tr("proxy.public.field.account_id")) {
                TextField(
                    L10n.tr("proxy.public.field.account_id_placeholder"),
                    text: Binding(
                        get: { model.cloudflaredNamedInput.accountID },
                        set: { model.cloudflaredNamedInput.accountID = $0 }
                    )
                )
                .frostedRoundedInput()
                .disabled(!model.canEditCloudflaredInput)
            }

            ProxyFieldGroup(title: L10n.tr("proxy.public.field.zone_id")) {
                TextField(
                    L10n.tr("proxy.public.field.zone_id_placeholder"),
                    text: Binding(
                        get: { model.cloudflaredNamedInput.zoneID },
                        set: { model.cloudflaredNamedInput.zoneID = $0 }
                    )
                )
                .frostedRoundedInput()
                .disabled(!model.canEditCloudflaredInput)
            }

            ProxyFieldGroup(title: L10n.tr("proxy.public.field.hostname")) {
                TextField(
                    L10n.tr("proxy.public.field.hostname_placeholder"),
                    text: Binding(
                        get: { model.cloudflaredNamedInput.hostname },
                        set: { model.updateCloudflaredNamedHostname($0) }
                    )
                )
                .frostedRoundedInput()
                .disabled(!model.canEditCloudflaredInput)
            }
        }
    }

    private var toolbar: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 10) {
            http2ToggleRow
            publicAccessActionStrip
        }
        #else
        HStack(spacing: 10) {
            http2ToggleRow
            Spacer(minLength: 0)
            publicAccessActionStrip
        }
        #endif
    }

    private var http2ToggleRow: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("proxy.toggle.use_http2"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            PublicAccessSwitchPill(
                isOn: Binding(
                    get: { model.cloudflaredUseHTTP2 },
                    set: { model.updateCloudflaredUseHTTP2($0) }
                )
            )
            .disabled(!model.canEditCloudflaredInput)
        }
    }

    private var publicAccessActionStrip: some View {
        ProxyActionStrip(
            buttons: model.publicAccessActionButtons,
            onAction: model.handlePublicAccessAction
        )
    }

    private var statusGrid: some View {
        LazyVStack(spacing: 10) {
            ProxyInfoCard(
                title: L10n.tr("proxy.public.status_title"),
                headline: model.cloudflaredStatus.running ? L10n.tr("proxy.status.running") : L10n.tr("proxy.status.stopped"),
                detailText: model.cloudflaredStatus.running
                    ? L10n.tr("proxy.public.status_running_message")
                    : L10n.tr("proxy.public.status_stopped_message"),
                headlineFont: .title3.weight(.semibold),
                detailFont: .subheadline,
                headlineLineLimit: 2
            )

            ProxyInfoCard(
                title: L10n.tr("proxy.public.url_title"),
                headline: model.cloudflaredStatus.publicURL ?? L10n.tr("proxy.value.generated_after_start"),
                detailText: "",
                headlineFont: .title3.weight(.semibold),
                headlineLineLimit: 2,
                headlineTruncationMode: .middle,
                canCopy: model.cloudflaredStatus.publicURL != nil,
                allowsTextSelection: true
            ) {
                onCopy(model.cloudflaredStatus.publicURL)
            }

            ProxyInfoCard(
                title: L10n.tr("proxy.public.install_path_title"),
                headline: model.cloudflaredStatus.binaryPath ?? L10n.tr("proxy.public.not_detected"),
                detailText: "",
                headlineFont: .title3.weight(.semibold),
                headlineLineLimit: 2,
                headlineTruncationMode: .middle
            )

            ProxyInfoCard(
                title: L10n.tr("proxy.detail.last_error"),
                headline: model.cloudflaredStatus.lastError ?? L10n.tr("common.none"),
                detailText: "",
                headlineFont: .title3.weight(.semibold),
                headlineLineLimit: 2
            )
        }
    }

    private func callout(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }
}
