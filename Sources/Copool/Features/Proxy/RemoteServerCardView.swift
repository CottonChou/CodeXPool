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
                label: draft.label,
                sshUser: draft.sshUser,
                host: draft.host,
                listenPort: draft.listenPort,
                isExpanded: isExpanded,
                status: status,
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
                    scrollable: true,
                    onAction: handleRemoteAction
                )
                RemoteServerStatusGrid(status: status)
                RemoteServerDetailGrid(status: status)
                RemoteServerLogsSection(logs: logs)
                RemoteServerErrorSection(message: status?.lastError ?? L10n.tr("common.none"))
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

private struct RemoteServerHeader: View {
    let label: String
    let sshUser: String
    let host: String
    let listenPort: Int
    let isExpanded: Bool
    let status: RemoteProxyStatus?
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.isEmpty ? RemoteServerConfiguration.defaultLabel : label)
                    .font(.headline)
                if !isExpanded {
                    Text("\(sshUser)@\(host):\(listenPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            CollapseChevronButton(isExpanded: isExpanded, action: onToggle)
            Text(RemoteServerConfiguration.statusLabel(status))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frostedCapsuleSurface(
                    prominent: status?.running == true,
                    tint: status?.running == true ? .green : .gray
                )
        }
    }
}

private struct RemoteServerFieldGrid: View {
    @Binding var draft: RemoteServerConfig

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyRemoteFieldMinWidth), spacing: 8)],
            spacing: 8
        ) {
            ProxyFieldGroup(title: "Name", style: .uppercaseCaption) {
                TextField("tokyo-01", text: $draft.label)
                    .frostedRoundedInput()
            }
            ProxyFieldGroup(title: "Host", style: .uppercaseCaption) {
                TextField("1.2.3.4", text: $draft.host)
                    .frostedRoundedInput()
            }
            ProxyFieldGroup(title: "SSH Port", style: .uppercaseCaption) {
                TextField("22", value: $draft.sshPort, format: .number.grouping(.never))
                    .frostedRoundedInput()
            }
            ProxyFieldGroup(title: "SSH User", style: .uppercaseCaption) {
                TextField(RemoteServerConfiguration.defaultSSHUser, text: $draft.sshUser)
                    .frostedRoundedInput()
            }
            ProxyFieldGroup(title: "Deploy Dir", style: .uppercaseCaption) {
                TextField(RemoteServerConfiguration.defaultRemoteDir, text: $draft.remoteDir)
                    .frostedRoundedInput()
            }
            ProxyFieldGroup(title: "Proxy Port", style: .uppercaseCaption) {
                TextField(
                    String(RemoteServerConfiguration.defaultProxyPort),
                    value: $draft.listenPort,
                    format: .number.grouping(.never)
                )
                .frostedRoundedInput()
            }
        }
    }
}

private struct RemoteServerAuthSection: View {
    @Binding var draft: RemoteServerConfig
    let onChooseIdentityFile: () -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("SSH Auth", selection: $draft.authMode) {
                Text("Path").tag("keyPath")
                Text("Private key").tag("keyContent")
                Text("Password").tag("password")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)

            switch draft.authMode {
            case "keyContent":
                TextEditor(text: Binding(
                    get: { draft.privateKey ?? "" },
                    set: { draft.privateKey = $0 }
                ))
                .font(.caption.monospaced())
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frostedRoundedSurface(cornerRadius: 8)
            case "password":
                SecureField("SSH password", text: Binding(
                    get: { draft.password ?? "" },
                    set: { draft.password = $0 }
                ))
                .frostedRoundedInput()
            default:
                HStack(spacing: 8) {
                    TextField("~/.ssh/id_ed25519", text: Binding(
                        get: { draft.identityFile ?? "" },
                        set: { draft.identityFile = $0 }
                    ))
                    .frostedRoundedInput()
                    #if canImport(AppKit)
                    Button {
                        if let path = onChooseIdentityFile() {
                            draft.identityFile = path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .liquidGlassActionButtonStyle()
                    .help("Choose key file")
                    #endif
                }
            }
        }
    }
}

private struct RemoteServerStatusGrid: View {
    let status: RemoteProxyStatus?

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyRemoteMetricMinWidth), spacing: 8)],
            spacing: 8
        ) {
            RemoteServerMetricCard(title: "Installed", value: RemoteServerConfiguration.boolText(status?.installed))
            RemoteServerMetricCard(title: "Systemd", value: RemoteServerConfiguration.boolText(status?.serviceInstalled))
            RemoteServerMetricCard(title: "Enabled on boot", value: RemoteServerConfiguration.boolText(status?.enabled))
            RemoteServerMetricCard(title: "Running", value: RemoteServerConfiguration.boolText(status?.running))
            RemoteServerMetricCard(title: "PID", value: status?.pid.map(String.init) ?? "--")
        }
    }
}

private struct RemoteServerMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: LayoutRules.proxyRemoteMetricHeight, alignment: .topLeading)
        .padding(8)
        .cardSurface(cornerRadius: 10)
    }
}

private struct RemoteServerDetailGrid: View {
    let status: RemoteProxyStatus?

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyRemoteDetailMinWidth), spacing: 8)],
            spacing: 8
        ) {
            ProxyCopyableValueCard(
                title: "Remote Base URL",
                value: status?.baseURL ?? "--",
                canCopy: status?.baseURL != nil,
                titleDisplayMode: .uppercased,
                cornerRadius: 10,
                padding: 10
            )
            ProxyCopyableValueCard(
                title: "Remote API key",
                value: status?.apiKey ?? "Generated after first start",
                canCopy: status?.apiKey != nil,
                titleDisplayMode: .uppercased,
                cornerRadius: 10,
                padding: 10
            )
            ProxyCopyableValueCard(
                title: "Service name",
                value: status?.serviceName ?? "Unknown",
                canCopy: status?.serviceName != nil,
                titleDisplayMode: .uppercased,
                cornerRadius: 10,
                padding: 10
            )
        }
    }
}

private struct RemoteServerLogsSection: View {
    let logs: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Remote logs")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("common.copy") {
                    PlatformClipboard.copy(logs)
                }
                .liquidGlassActionButtonStyle()
                .disabled((logs ?? "").isEmpty)
            }

            ScrollView(.vertical) {
                Text(logs?.isEmpty == false ? logs! : "Logs have not been loaded yet")
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: LayoutRules.proxyRemoteLogsHeight)
            .cardSurface(cornerRadius: 8)
            .scrollIndicators(.visible)
        }
    }
}

private struct RemoteServerErrorSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remote error")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .cardSurface(cornerRadius: 8)
        }
    }
}
