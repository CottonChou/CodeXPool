import Foundation

actor RemoteProxyService: RemoteProxyServiceProtocol {
    private let repoRoot: URL
    private let sourceAccountStorePath: URL
    private let fileManager: FileManager

    init(repoRoot: URL, sourceAccountStorePath: URL, fileManager: FileManager = .default) {
        self.repoRoot = repoRoot
        self.sourceAccountStorePath = sourceAccountStorePath
        self.fileManager = fileManager
    }

    func status(server: RemoteServerConfig) async -> RemoteProxyStatus {
        do {
            let normalized = try validate(server)
            let serviceName = systemdServiceName(for: normalized)
            let command = """
            DIR=\(shellQuote(normalized.remoteDir)); BIN="$DIR/codex-tools-proxyd"; KEYFILE="$DIR/api-proxy.key"; UNIT=\(shellQuote(serviceName)); \
            INSTALLED=0; SERVICE_INSTALLED=0; RUNNING=0; ENABLED=0; PID=""; API_KEY=""; \
            if [ -x "$BIN" ]; then INSTALLED=1; fi; \
            if command -v systemctl >/dev/null 2>&1; then \
              if [ -f "/etc/systemd/system/$UNIT" ] || [ -f "/lib/systemd/system/$UNIT" ]; then SERVICE_INSTALLED=1; fi; \
              ENABLED_STATE=$(systemctl is-enabled "$UNIT" 2>/dev/null || true); \
              if [ "$ENABLED_STATE" = "enabled" ]; then ENABLED=1; fi; \
              ACTIVE_STATE=$(systemctl is-active "$UNIT" 2>/dev/null || true); \
              if [ "$ACTIVE_STATE" = "active" ]; then RUNNING=1; fi; \
              PID=$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || true); \
              if [ "$PID" = "0" ]; then PID=""; fi; \
            fi; \
            if [ -f "$KEYFILE" ]; then API_KEY=$(cat "$KEYFILE" 2>/dev/null || true); fi; \
            printf 'installed=%s\\nservice_installed=%s\\nrunning=%s\\nenabled=%s\\npid=%s\\napi_key=%s\\n' "$INSTALLED" "$SERVICE_INSTALLED" "$RUNNING" "$ENABLED" "$PID" "$API_KEY"
            """

            let output = try runSSH(server: normalized, command: command)
            return parseStatusOutput(output, serviceName: serviceName, host: normalized.host, listenPort: normalized.listenPort)
        } catch {
            return RemoteProxyStatus(
                installed: false,
                serviceInstalled: false,
                running: false,
                enabled: false,
                serviceName: systemdServiceName(for: server),
                pid: nil,
                baseURL: "http://\(server.host):\(server.listenPort)/v1",
                apiKey: nil,
                lastError: error.localizedDescription
            )
        }
    }

    func deploy(server: RemoteServerConfig) async throws -> RemoteProxyStatus {
        let server = try validate(server)
        try ensureSSHToolsAvailable(for: server)

        let binaryPath = try ensureDaemonBinary()
        let serviceName = systemdServiceName(for: server)
        let serviceContent = renderSystemdUnit(server: server, serviceName: serviceName)

        let temp = fileManager.temporaryDirectory.appendingPathComponent("codex-tools-remote-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }

        let localBinary = temp.appendingPathComponent("codex-tools-proxyd", isDirectory: false)
        let localAccounts = temp.appendingPathComponent("accounts.json", isDirectory: false)
        let localService = temp.appendingPathComponent(serviceName, isDirectory: false)

        try fileManager.copyItem(at: binaryPath, to: localBinary)
        if fileManager.fileExists(atPath: sourceAccountStorePath.path) {
            try fileManager.copyItem(at: sourceAccountStorePath, to: localAccounts)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(AccountsStore())
            try data.write(to: localAccounts)
        }
        try serviceContent.write(to: localService, atomically: true, encoding: .utf8)

        let stageDir = "/tmp/codex-tools-remote-\(safeFragment(server.id))-\(Int(Date().timeIntervalSince1970))"
        _ = try runSSH(server: server, command: "mkdir -p \(shellQuote(stageDir))")

        try runSCP(server: server, localPath: localBinary.path, remotePath: "\(stageDir)/codex-tools-proxyd")
        try runSCP(server: server, localPath: localAccounts.path, remotePath: "\(stageDir)/accounts.json")
        try runSCP(server: server, localPath: localService.path, remotePath: "\(stageDir)/\(serviceName)")

        let installCommand = """
        mkdir -p \(shellQuote(server.remoteDir)); \
        mv \(shellQuote("\(stageDir)/codex-tools-proxyd")) \(shellQuote("\(server.remoteDir)/codex-tools-proxyd")); chmod 700 \(shellQuote("\(server.remoteDir)/codex-tools-proxyd")); \
        mv \(shellQuote("\(stageDir)/accounts.json")) \(shellQuote("\(server.remoteDir)/accounts.json")); chmod 600 \(shellQuote("\(server.remoteDir)/accounts.json")); \
        mv \(shellQuote("\(stageDir)/\(serviceName)")) \(shellQuote("/etc/systemd/system/\(serviceName)")); chmod 644 \(shellQuote("/etc/systemd/system/\(serviceName)")); \
        rm -rf \(shellQuote(stageDir)); \
        systemctl daemon-reload; \
        systemctl enable \(shellQuote(serviceName)) >/dev/null 2>&1 || true; \
        if systemctl is-active --quiet \(shellQuote(serviceName)); then systemctl restart \(shellQuote(serviceName)); else systemctl start \(shellQuote(serviceName)); fi
        """

        _ = try runSSH(server: server, command: withRootPrivileges(installCommand))

        return await status(server: server)
    }

    func start(server: RemoteServerConfig) async throws -> RemoteProxyStatus {
        let normalized = try validate(server)
        let serviceName = systemdServiceName(for: normalized)
        _ = try runSSH(server: normalized, command: withRootPrivileges("systemctl start \(shellQuote(serviceName))"))
        return await status(server: normalized)
    }

    func stop(server: RemoteServerConfig) async throws -> RemoteProxyStatus {
        let normalized = try validate(server)
        let serviceName = systemdServiceName(for: normalized)
        _ = try runSSH(server: normalized, command: withRootPrivileges("systemctl stop \(shellQuote(serviceName))"))
        return await status(server: normalized)
    }

    func readLogs(server: RemoteServerConfig, lines: Int) async throws -> String {
        let normalized = try validate(server)
        let serviceName = systemdServiceName(for: normalized)
        let count = min(max(lines, 20), 400)

        return try runSSH(
            server: normalized,
            command: withRootPrivileges("journalctl -u \(shellQuote(serviceName)) -n \(count) --no-pager")
        )
    }

    private func validate(_ server: RemoteServerConfig) throws -> RemoteServerConfig {
        var normalized = server
        normalized.label = normalized.label.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.host = normalized.host.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.sshUser = normalized.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.remoteDir = normalized.remoteDir.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.identityFile = normalized.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.privateKey = normalized.privateKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.password = normalized.password?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.label.isEmpty else { throw AppError.invalidData(L10n.tr("error.remote.label_empty")) }
        guard !normalized.host.isEmpty else { throw AppError.invalidData(L10n.tr("error.remote.host_empty")) }
        guard !normalized.sshUser.isEmpty else { throw AppError.invalidData(L10n.tr("error.remote.ssh_user_empty")) }
        guard !normalized.remoteDir.isEmpty else { throw AppError.invalidData(L10n.tr("error.remote.remote_dir_empty")) }
        guard normalized.sshPort > 0 else { throw AppError.invalidData(L10n.tr("error.remote.ssh_port_invalid")) }
        guard normalized.listenPort > 0 else { throw AppError.invalidData(L10n.tr("error.remote.listen_port_invalid")) }

        switch normalized.authMode {
        case "keyContent":
            guard normalized.privateKey?.isEmpty == false else {
                throw AppError.invalidData(L10n.tr("error.remote.private_key_content_empty"))
            }
        case "password":
            guard normalized.password?.isEmpty == false else {
                throw AppError.invalidData(L10n.tr("error.remote.password_empty"))
            }
        default:
            guard normalized.identityFile?.isEmpty == false else {
                throw AppError.invalidData(L10n.tr("error.remote.identity_file_empty"))
            }
        }

        return normalized
    }

    private func ensureSSHToolsAvailable(for server: RemoteServerConfig) throws {
        guard CommandRunner.resolveExecutable("ssh") != nil else {
            throw AppError.io(L10n.tr("error.remote.ssh_not_found"))
        }
        guard CommandRunner.resolveExecutable("scp") != nil else {
            throw AppError.io(L10n.tr("error.remote.scp_not_found"))
        }
        if server.authMode == "password", CommandRunner.resolveExecutable("sshpass") == nil {
            throw AppError.io(L10n.tr("error.remote.sshpass_required"))
        }
    }

    private func ensureDaemonBinary() throws -> URL {
        let manifestPath = repoRoot.appendingPathComponent("src-tauri/proxyd/Cargo.toml", isDirectory: false)
        let binaryPath = repoRoot.appendingPathComponent("src-tauri/proxyd/target/release/codex-tools-proxyd", isDirectory: false)

        if fileManager.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        _ = try CommandRunner.runChecked(
            "/usr/bin/env",
            arguments: ["cargo", "build", "--manifest-path", manifestPath.path, "--release"],
            currentDirectory: repoRoot,
            errorPrefix: L10n.tr("error.remote.build_proxyd_failed")
        )

        guard fileManager.fileExists(atPath: binaryPath.path) else {
            throw AppError.io(L10n.tr("error.remote.proxyd_not_found_after_build"))
        }

        return binaryPath
    }

    private func runSSH(server: RemoteServerConfig, command: String) throws -> String {
        var temporaryKey: URL?
        defer {
            if let temporaryKey {
                try? fileManager.removeItem(at: temporaryKey)
            }
        }

        let identityPath: String?
        switch server.authMode {
        case "keyContent":
            let tempKey = fileManager.temporaryDirectory.appendingPathComponent("codex-tools-key-\(UUID().uuidString)", isDirectory: false)
            try server.privateKey?.write(to: tempKey, atomically: true, encoding: .utf8)
            #if canImport(Darwin)
            _ = chmod(tempKey.path, S_IRUSR | S_IWUSR)
            #endif
            temporaryKey = tempKey
            identityPath = tempKey.path
        case "password":
            identityPath = nil
        default:
            identityPath = server.identityFile
        }

        var args: [String] = []
        if server.authMode == "password", let password = server.password {
            args.append(contentsOf: ["sshpass", "-p", password, "ssh"])
        } else {
            args.append("ssh")
        }

        args.append(contentsOf: ["-p", String(server.sshPort), "-o", "StrictHostKeyChecking=accept-new"])
        if let identityPath {
            args.append(contentsOf: ["-i", identityPath])
        }
        args.append("\(server.sshUser)@\(server.host)")
        args.append(command)

        let result = try CommandRunner.run("/usr/bin/env", arguments: args)
        guard result.status == 0 else {
            throw AppError.io(L10n.tr("error.remote.ssh_command_failed_format", result.stderr.isEmpty ? result.stdout : result.stderr))
        }
        return result.stdout
    }

    private func runSCP(server: RemoteServerConfig, localPath: String, remotePath: String) throws {
        var temporaryKey: URL?
        defer {
            if let temporaryKey {
                try? fileManager.removeItem(at: temporaryKey)
            }
        }

        let identityPath: String?
        switch server.authMode {
        case "keyContent":
            let tempKey = fileManager.temporaryDirectory.appendingPathComponent("codex-tools-key-\(UUID().uuidString)", isDirectory: false)
            try server.privateKey?.write(to: tempKey, atomically: true, encoding: .utf8)
            #if canImport(Darwin)
            _ = chmod(tempKey.path, S_IRUSR | S_IWUSR)
            #endif
            temporaryKey = tempKey
            identityPath = tempKey.path
        case "password":
            identityPath = nil
        default:
            identityPath = server.identityFile
        }

        var args: [String] = []
        if server.authMode == "password", let password = server.password {
            args.append(contentsOf: ["sshpass", "-p", password, "scp"])
        } else {
            args.append("scp")
        }

        args.append(contentsOf: ["-P", String(server.sshPort), "-o", "StrictHostKeyChecking=accept-new"])
        if let identityPath {
            args.append(contentsOf: ["-i", identityPath])
        }

        args.append(localPath)
        args.append("\(server.sshUser)@\(server.host):\(remotePath)")

        let result = try CommandRunner.run("/usr/bin/env", arguments: args)
        guard result.status == 0 else {
            throw AppError.io(L10n.tr("error.remote.scp_failed_format", result.stderr.isEmpty ? result.stdout : result.stderr))
        }
    }

    private func parseStatusOutput(_ output: String, serviceName: String, host: String, listenPort: Int) -> RemoteProxyStatus {
        var installed = false
        var serviceInstalled = false
        var running = false
        var enabled = false
        var pid: Int?
        var apiKey: String?

        for line in output.split(whereSeparator: { $0.isNewline }) {
            let text = String(line)
            if let value = text.split(separator: "=", maxSplits: 1).dropFirst().first {
                if text.hasPrefix("installed=") {
                    installed = value == "1"
                } else if text.hasPrefix("service_installed=") {
                    serviceInstalled = value == "1"
                } else if text.hasPrefix("running=") {
                    running = value == "1"
                } else if text.hasPrefix("enabled=") {
                    enabled = value == "1"
                } else if text.hasPrefix("pid=") {
                    pid = Int(value)
                } else if text.hasPrefix("api_key=") {
                    let key = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
                    apiKey = key.isEmpty ? nil : key
                }
            }
        }

        return RemoteProxyStatus(
            installed: installed,
            serviceInstalled: serviceInstalled,
            running: running,
            enabled: enabled,
            serviceName: serviceName,
            pid: pid,
            baseURL: "http://\(host):\(listenPort)/v1",
            apiKey: apiKey,
            lastError: nil
        )
    }

    private func systemdServiceName(for server: RemoteServerConfig) -> String {
        "codex-tools-proxyd-\(safeFragment(server.id)).service"
    }

    private func safeFragment(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(chars)
        return sanitized.isEmpty ? "default" : sanitized
    }

    private func renderSystemdUnit(server: RemoteServerConfig, serviceName: String) -> String {
        """
        [Unit]
        Description=Codex Tools Remote API Proxy (\(serviceName))
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        WorkingDirectory=\(server.remoteDir)
        ExecStart=\(server.remoteDir)/codex-tools-proxyd serve --data-dir \(server.remoteDir) --host 0.0.0.0 --port \(server.listenPort) --no-sync-current-auth
        Restart=always
        RestartSec=3
        Environment=RUST_LOG=info

        [Install]
        WantedBy=multi-user.target
        """
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func withRootPrivileges(_ command: String) -> String {
        "if [ \"$(id -u)\" = \"0\" ]; then \(command); else sudo sh -lc \(shellQuote(command)); fi"
    }
}
