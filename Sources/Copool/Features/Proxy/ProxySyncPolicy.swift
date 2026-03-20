import Foundation

enum ProxySyncPolicy {
    enum RemoteControl {
        static let snapshotSyncInterval: Duration = .seconds(1)
        static let snapshotFreshnessWindowMilliseconds: Int64 = 5_000
        static let remoteStatusesFreshnessWindowMilliseconds: Int64 = 12_000
        static let commandAckPollLimit = 24
        static let commandAckPollInterval: Duration = .milliseconds(250)
        static let logAckPollLimit = 36
        static let logAckPollInterval: Duration = .milliseconds(250)
    }

    enum Configuration {
        static let debounceInterval: Duration = .milliseconds(350)
    }
}
