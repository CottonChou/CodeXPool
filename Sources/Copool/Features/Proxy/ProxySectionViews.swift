import SwiftUI

struct ApiProxySectionView: View {
    @ObservedObject var model: ProxyPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.apiProxySectionExpanded {
                proxyHeroContent
                proxyDetailCards
            } else {
                collapsedSummaryPills
            }
        }
        .padding(16)
        .cardSurface(cornerRadius: LayoutRules.cardRadius)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("proxy.section.api_proxy"))
                .font(.headline)

            Spacer(minLength: 0)

            CollapseChevronButton(isExpanded: model.apiProxySectionExpanded) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.apiProxySectionExpanded.toggle()
                }
            }
        }
    }

    private var collapsedSummaryPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ProxyStatusPill(isRunning: model.proxyStatus.running)
                ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProxyStatusPill(isRunning: model.proxyStatus.running)
                    ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                }
                ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
            }
        }
    }

    private var proxyHeroContent: some View {
        VStack(spacing: 12) {
            expandedSummaryPills

            HStack(spacing: 10) {
                TextField(
                    "8787",
                    text: Binding(
                        get: { model.preferredPortText },
                        set: { model.updatePreferredPortText($0) }
                    )
                )
                .frostedCapsuleInput()
                .frame(width: LayoutRules.proxyHeroPortFieldWidth)

                ProxyActionStrip(
                    buttons: model.apiProxyActionButtons,
                    onAction: model.handleAPIProxyAction
                )
            }

            HStack {
                Text("proxy.start_on_launch")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { model.autoStartProxy },
                    set: { value in
                        Task { await model.setAutoStartProxy(value) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var expandedSummaryPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ProxyStatusPill(isRunning: model.proxyStatus.running)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                    ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ProxyStatusPill(isRunning: model.proxyStatus.running)
                HStack(spacing: 8) {
                    ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                    ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
                }
            }
        }
    }

    private var proxyDetailCards: some View {
        LazyVStack(spacing: LayoutRules.proxyDetailCardSpacing) {
            ProxyCopyableValueCard(
                title: L10n.tr("proxy.detail.base_url"),
                value: model.proxyStatus.baseURL ?? L10n.tr("proxy.value.generated_after_start"),
                canCopy: model.proxyStatus.baseURL != nil
            )

            ProxyCopyableValueCard(
                title: L10n.tr("proxy.detail.api_key"),
                value: model.proxyStatus.apiKey ?? L10n.tr("proxy.value.generated_after_first_start"),
                canCopy: model.proxyStatus.apiKey != nil
            ) {
                Button("common.refresh") {
                    Task { await model.refreshAPIKey() }
                }
                .liquidGlassActionButtonStyle()
                .disabled(model.loading)
            }

            ProxyInfoCard(
                title: L10n.tr("proxy.detail.active_routed_account"),
                headline: model.proxyStatus.activeAccountLabel ?? L10n.tr("proxy.info.no_request_matched"),
                detailText: model.proxyStatus.activeAccountID ?? L10n.tr("proxy.info.active_account_hint")
            )
            ProxyInfoCard(
                title: L10n.tr("proxy.detail.last_error"),
                headline: model.proxyStatus.lastError ?? L10n.tr("common.none"),
                detailText: ""
            )
        }
    }
}

struct RemoteServersSectionView: View {
    @ObservedObject var model: ProxyPageModel

    var body: some View {
        SectionCard(
            title: L10n.tr("proxy.section.remote_servers"),
            headerTrailing: {
                Button("proxy.action.add_server") {
                    Task { await model.addRemoteServer() }
                }
                .liquidGlassActionButtonStyle(prominent: true)
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("proxy.remote.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.remoteServers.isEmpty {
                    EmptyStateView(
                        title: L10n.tr("proxy.remote.empty.title"),
                        message: L10n.tr("proxy.remote.empty.message")
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.remoteServers) { server in
                            RemoteServerCardView(
                                server: server,
                                status: model.remoteStatuses[server.id],
                                logs: model.remoteLogs[server.id],
                                activeAction: model.remoteActions[server.id],
                                onSave: { updated in Task { await model.saveRemoteServer(updated) } },
                                onRemove: { id in Task { await model.removeRemoteServer(id: id) } },
                                onRefresh: { Task { await model.refreshRemote(server: server) } },
                                onDeploy: { Task { await model.deployRemote(server: server) } },
                                onStart: { Task { await model.startRemote(server: server) } },
                                onStop: { Task { await model.stopRemote(server: server) } },
                                onLogs: { Task { await model.readRemoteLogs(server: server) } }
                            )
                        }
                    }
                }
            }
        }
    }
}
