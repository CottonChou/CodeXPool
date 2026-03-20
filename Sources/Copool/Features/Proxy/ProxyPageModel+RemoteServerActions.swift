import Foundation

extension ProxyPageModel {
    func addRemoteServer() async {
        if usesRemoteMacControl {
            await performRemoteCommand(
                kind: .addRemoteServer,
                remoteServer: RemoteServerConfiguration.makeDraft(),
                successNotice: L10n.tr("settings.notice.remote_servers_saved")
            )
            return
        }
        do {
            let snapshot = try await performLocalCommand(
                kind: .addRemoteServer,
                remoteServer: RemoteServerConfiguration.makeDraft()
            )
            applyRemoteSnapshot(snapshot)
            notice = NoticeMessage(style: .success, text: L10n.tr("settings.notice.remote_servers_saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveRemoteServer(_ server: RemoteServerConfig) async {
        if usesRemoteMacControl {
            await performRemoteCommand(
                kind: .saveRemoteServer,
                remoteServer: RemoteServerConfiguration.normalize(server),
                successNotice: L10n.tr("settings.notice.remote_servers_saved")
            )
            return
        }
        remoteActions[server.id] = .save
        defer { remoteActions.removeValue(forKey: server.id) }
        do {
            let snapshot = try await performLocalCommand(
                kind: .saveRemoteServer,
                remoteServer: RemoteServerConfiguration.normalize(server)
            )
            applyRemoteSnapshot(snapshot)
            notice = NoticeMessage(style: .success, text: L10n.tr("settings.notice.remote_servers_saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func removeRemoteServer(id: String) async {
        if usesRemoteMacControl {
            await performRemoteCommand(
                kind: .removeRemoteServer,
                remoteServerID: id,
                successNotice: L10n.tr("proxy.notice.remote_server_removed")
            )
            return
        }
        remoteActions[id] = .remove
        defer { remoteActions.removeValue(forKey: id) }
        do {
            let snapshot = try await performLocalCommand(
                kind: .removeRemoteServer,
                remoteServerID: id
            )
            applyRemoteSnapshot(snapshot)
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_server_removed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshAllRemoteStatuses() async {
        guard canManageRemoteServers else {
            remoteStatuses = [:]
            return
        }
        if usesRemoteMacControl {
            await refreshRemoteSnapshot(showErrors: false)
            return
        }
        remoteStatuses = await coordinator.remoteStatuses(for: remoteServers)
    }

    func refreshRemote(server: RemoteServerConfig) async {
        guard canManageRemoteServers else { return }
        if usesRemoteMacControl {
            await performRemoteCommand(kind: .refreshRemote, remoteServerID: server.id)
            return
        }
        remoteActions[server.id] = .refresh
        defer { remoteActions.removeValue(forKey: server.id) }
        do {
            let snapshot = try await performLocalCommand(
                kind: .refreshRemote,
                remoteServerID: server.id
            )
            applyRemoteSnapshot(snapshot)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deployRemote(server: RemoteServerConfig) async {
        guard canManageRemoteServers else { return }
        if usesRemoteMacControl {
            await performRemoteCommand(
                kind: .deployRemote,
                remoteServerID: server.id,
                successNotice: L10n.tr("proxy.notice.remote_deploy_done_format", server.label),
                pendingNotice: L10n.tr("proxy.notice.remote_deploying_format", server.label)
            )
            return
        }
        remoteActions[server.id] = .deploy
        defer { remoteActions.removeValue(forKey: server.id) }
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.remote_deploying_format", server.label))

        do {
            let snapshot = try await performLocalCommand(
                kind: .deployRemote,
                remoteServerID: server.id
            )
            applyRemoteSnapshot(snapshot)
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_deploy_done_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startRemote(server: RemoteServerConfig) async {
        guard canManageRemoteServers else { return }
        if usesRemoteMacControl {
            await performRemoteCommand(
                kind: .startRemote,
                remoteServerID: server.id,
                successNotice: L10n.tr("proxy.notice.remote_started_format", server.label)
            )
            return
        }
        remoteActions[server.id] = .start
        defer { remoteActions.removeValue(forKey: server.id) }

        do {
            let snapshot = try await performLocalCommand(
                kind: .startRemote,
                remoteServerID: server.id
            )
            applyRemoteSnapshot(snapshot)
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.remote_started_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopRemote(server: RemoteServerConfig) async {
        guard canManageRemoteServers else { return }
        if usesRemoteMacControl {
            await performRemoteCommand(
                kind: .stopRemote,
                remoteServerID: server.id,
                successNotice: L10n.tr("proxy.notice.remote_stopped_format", server.label)
            )
            return
        }
        remoteActions[server.id] = .stop
        defer { remoteActions.removeValue(forKey: server.id) }

        do {
            let snapshot = try await performLocalCommand(
                kind: .stopRemote,
                remoteServerID: server.id
            )
            applyRemoteSnapshot(snapshot)
            notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.remote_stopped_format", server.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func readRemoteLogs(server: RemoteServerConfig) async {
        guard canManageRemoteServers else { return }
        if usesRemoteMacControl {
            remoteActions[server.id] = .logs
            defer { remoteActions.removeValue(forKey: server.id) }

            await performRemoteLogCommand(
                serverID: server.id,
                logLines: 120
            )
            return
        }
        remoteActions[server.id] = .logs
        defer { remoteActions.removeValue(forKey: server.id) }

        do {
            let snapshot = try await performLocalCommand(
                kind: .readRemoteLogs,
                remoteServerID: server.id,
                logLines: 120
            )
            applyRemoteSnapshot(snapshot)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
