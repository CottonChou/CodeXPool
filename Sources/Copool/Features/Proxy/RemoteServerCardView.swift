import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct RemoteServerCardView: View {
    let server: RemoteServerConfig
    let status: RemoteProxyStatus?
    let logs: String?
    let activeAction: RemoteServerAction?
    let onSave: (RemoteServerConfig) -> Void
    let onRemove: (String) -> Void
    let onRefresh: () -> Void
    let onDeploy: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLogs: () -> Void

    @State private var draft: RemoteServerConfig
    @State private var isExpanded: Bool

    init(
        server: RemoteServerConfig,
        status: RemoteProxyStatus?,
        logs: String?,
        activeAction: RemoteServerAction?,
        onSave: @escaping (RemoteServerConfig) -> Void,
        onRemove: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onDeploy: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onLogs: @escaping () -> Void
    ) {
        self.server = server
        self.status = status
        self.logs = logs
        self.activeAction = activeAction
        self.onSave = onSave
        self.onRemove = onRemove
        self.onRefresh = onRefresh
        self.onDeploy = onDeploy
        self.onStart = onStart
        self.onStop = onStop
        self.onLogs = onLogs
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
                    onChooseIdentityFile: chooseIdentityFilePath
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
            onSave(draft)
        case .remove:
            onRemove(server.id)
        case .refresh:
            onRefresh()
        case .deploy:
            onDeploy()
        case .start:
            onStart()
        case .stop:
            onStop()
        case .logs:
            onLogs()
        }
    }

    private func chooseIdentityFilePath() -> String? {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select SSH key file"
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url?.path
        #else
        return nil
        #endif
    }
}
