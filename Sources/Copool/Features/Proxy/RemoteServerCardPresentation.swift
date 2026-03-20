import Foundation

struct RemoteServerHeaderPresentation: Equatable {
    let title: String
    let subtitle: String?
    let statusLabel: String
    let isRunning: Bool
}

struct RemoteServerMetricDescriptor: Identifiable, Equatable {
    let title: String
    let value: String

    var id: String { title }
}

struct RemoteServerDetailDescriptor: Identifiable, Equatable {
    let title: String
    let value: String
    let canCopy: Bool

    var id: String { title }
}

struct RemoteServerLogsPresentation: Equatable {
    let content: String
    let canCopy: Bool
}

enum RemoteServerCardPresentation {
    static func header(
        label: String,
        sshUser: String,
        host: String,
        listenPort: Int,
        isExpanded: Bool,
        status: RemoteProxyStatus?
    ) -> RemoteServerHeaderPresentation {
        RemoteServerHeaderPresentation(
            title: label.isEmpty ? RemoteServerConfiguration.defaultLabel : label,
            subtitle: isExpanded ? nil : "\(sshUser)@\(host):\(listenPort)",
            statusLabel: RemoteServerConfiguration.statusLabel(status),
            isRunning: status?.running == true
        )
    }

    static func metrics(
        status: RemoteProxyStatus?
    ) -> [RemoteServerMetricDescriptor] {
        [
            RemoteServerMetricDescriptor(title: "Installed", value: RemoteServerConfiguration.boolText(status?.installed)),
            RemoteServerMetricDescriptor(title: "Systemd", value: RemoteServerConfiguration.boolText(status?.serviceInstalled)),
            RemoteServerMetricDescriptor(title: "Enabled on boot", value: RemoteServerConfiguration.boolText(status?.enabled)),
            RemoteServerMetricDescriptor(title: "Running", value: RemoteServerConfiguration.boolText(status?.running)),
            RemoteServerMetricDescriptor(title: "PID", value: status?.pid.map(String.init) ?? "--")
        ]
    }

    static func details(
        status: RemoteProxyStatus?
    ) -> [RemoteServerDetailDescriptor] {
        [
            RemoteServerDetailDescriptor(
                title: "Remote Base URL",
                value: status?.baseURL ?? "--",
                canCopy: status != nil
            ),
            RemoteServerDetailDescriptor(
                title: "Remote API key",
                value: status?.apiKey ?? "Generated after first start",
                canCopy: status?.apiKey != nil
            ),
            RemoteServerDetailDescriptor(
                title: "Service name",
                value: status?.serviceName ?? "Unknown",
                canCopy: status != nil
            )
        ]
    }

    static func logs(
        logs: String?
    ) -> RemoteServerLogsPresentation {
        let content = logs?.isEmpty == false
            ? logs!
            : "Logs have not been loaded yet"
        return RemoteServerLogsPresentation(
            content: content,
            canCopy: !(logs ?? "").isEmpty
        )
    }
}
