struct ProxyRemoteSnapshotPresentationState: Equatable {
    var proxyStatus: ApiProxyStatus
    var preferredPortText: String
    var autoStartProxy: Bool
    var cloudflaredStatus: CloudflaredStatus
    var cloudflaredTunnelMode: CloudflaredTunnelMode
    var cloudflaredNamedHostname: String
    var cloudflaredUseHTTP2: Bool
    var publicAccessEnabled: Bool
    var remoteServers: [RemoteServerConfig]
    var remoteStatuses: [String: RemoteProxyStatus]
    var remoteLogs: [String: String]

    init(
        proxyStatus: ApiProxyStatus,
        preferredPortText: String,
        autoStartProxy: Bool,
        cloudflaredStatus: CloudflaredStatus,
        cloudflaredTunnelMode: CloudflaredTunnelMode,
        cloudflaredNamedHostname: String,
        cloudflaredUseHTTP2: Bool,
        publicAccessEnabled: Bool,
        remoteServers: [RemoteServerConfig],
        remoteStatuses: [String: RemoteProxyStatus],
        remoteLogs: [String: String]
    ) {
        self.proxyStatus = proxyStatus
        self.preferredPortText = preferredPortText
        self.autoStartProxy = autoStartProxy
        self.cloudflaredStatus = cloudflaredStatus
        self.cloudflaredTunnelMode = cloudflaredTunnelMode
        self.cloudflaredNamedHostname = cloudflaredNamedHostname
        self.cloudflaredUseHTTP2 = cloudflaredUseHTTP2
        self.publicAccessEnabled = publicAccessEnabled
        self.remoteServers = remoteServers
        self.remoteStatuses = remoteStatuses
        self.remoteLogs = remoteLogs
    }

    init(snapshot: ProxyControlSnapshot) {
        proxyStatus = snapshot.proxyStatus
        preferredPortText = ProxyConfiguration.normalizePreferredPortText(
            snapshot.preferredProxyPortText
                ?? snapshot.preferredProxyPort.map(String.init)
                ?? snapshot.proxyStatus.port.map(String.init)
                ?? String(RemoteServerConfiguration.defaultProxyPort)
        )
        autoStartProxy = snapshot.autoStartProxy
        cloudflaredStatus = snapshot.cloudflaredStatus
        cloudflaredTunnelMode = snapshot.cloudflaredTunnelMode
        cloudflaredNamedHostname = snapshot.cloudflaredNamedInput.hostname
        cloudflaredUseHTTP2 = snapshot.cloudflaredUseHTTP2
        publicAccessEnabled = snapshot.publicAccessEnabled
        remoteServers = snapshot.remoteServers
        remoteStatuses = snapshot.remoteStatuses
        remoteLogs = snapshot.remoteLogs
    }
}
