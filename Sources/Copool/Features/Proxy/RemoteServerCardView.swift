import SwiftUI

struct RemoteServerCardView: View {
    let server: RemoteServerConfig
    let status: RemoteProxyStatus?
    let logs: String?
    let activeAction: RemoteServerAction?
    let actions: RemoteServerCardActions

    @State private var draft: RemoteServerConfig
    @State private var isExpanded: Bool

    init(
        server: RemoteServerConfig,
        status: RemoteProxyStatus?,
        logs: String?,
        activeAction: RemoteServerAction?,
        actions: RemoteServerCardActions
    ) {
        self.server = server
        self.status = status
        self.logs = logs
        self.activeAction = activeAction
        self.actions = actions
        _draft = State(initialValue: server)
        _isExpanded = State(initialValue: RemoteServerConfiguration.isPlaceholderDraft(server))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteServerHeader(
                presentation: RemoteServerCardPresentation.header(
                    label: draft.label,
                    sshUser: draft.sshUser,
                    host: draft.host,
                    listenPort: draft.listenPort,
                    isExpanded: isExpanded,
                    status: status
                ),
                isExpanded: isExpanded,
                onToggle: toggleExpanded
            )

            if isExpanded {
                RemoteServerFieldGrid(draft: $draft)
                RemoteServerAuthSection(
                    draft: $draft,
                    onChooseIdentityFile: actions.onChooseIdentityFile
                )
                ProxyActionStrip(
                    buttons: ProxyActionPresentation.remoteServerButtons(
                        isRunning: status?.running == true,
                        activeAction: activeAction
                    ),
                    layout: .adaptiveGrid(
                        minimumColumnWidth: LayoutRules.proxyRemoteActionGridMinWidth
                    ),
                    onAction: handleRemoteAction
                )
                RemoteServerStatusGrid(
                    descriptors: RemoteServerCardPresentation.metrics(status: status)
                )
                RemoteServerDetailGrid(
                    descriptors: RemoteServerCardPresentation.details(status: status)
                )
                RemoteServerLogsSection(
                    presentation: RemoteServerCardPresentation.logs(logs: logs)
                )
                RemoteServerErrorSection(
                    message: status?.lastError ?? L10n.tr("common.none")
                )
            }
        }
        .padding(10)
        .cardSurface(cornerRadius: 10)
        .onChange(of: server) { _, newValue in
            draft = newValue
            if RemoteServerConfiguration.isPlaceholderDraft(draft) {
                isExpanded = true
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }

    private func handleRemoteAction(_ intent: RemoteServerAction) async {
        switch intent {
        case .save:
            actions.onSave(draft)
        case .remove:
            actions.onRemove(server.id)
        case .refresh:
            actions.onRefresh()
        case .deploy:
            actions.onDeploy()
        case .start:
            actions.onStart()
        case .stop:
            actions.onStop()
        case .logs:
            actions.onLogs()
        }
    }
}
