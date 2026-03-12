import Foundation

actor CloudflaredService: CloudflaredServiceProtocol {
    private let paths: FileSystemPaths
    private let fileManager: FileManager

    private var process: Process?
    private var mode: CloudflaredTunnelMode?
    private var useHTTP2 = false
    private var customHostname: String?
    private var logPath: URL?
    private var lastError: String?

    init(paths: FileSystemPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func status() async -> CloudflaredStatus {
        let binaryPath = CommandRunner.resolveExecutable("cloudflared")
        let running = process?.isRunning == true

        if !running {
            process = nil
        }

        let publicURL = logPath.flatMap { parsePublicURL(from: $0) }

        return CloudflaredStatus(
            installed: binaryPath != nil,
            binaryPath: binaryPath,
            running: running,
            tunnelMode: running ? mode : nil,
            publicURL: publicURL,
            customHostname: running ? customHostname : nil,
            useHTTP2: running ? useHTTP2 : false,
            lastError: lastError
        )
    }

    func install() async throws -> CloudflaredStatus {
        if CommandRunner.resolveExecutable("cloudflared") != nil {
            return await status()
        }

        #if os(macOS)
        _ = try CommandRunner.runChecked(
            "/usr/bin/env",
            arguments: ["brew", "install", "cloudflared"],
            errorPrefix: L10n.tr("error.cloudflared.install_failed")
        )
        #else
        throw AppError.io(L10n.tr("error.cloudflared.install_unsupported_platform"))
        #endif

        return await status()
    }

    func start(_ input: StartCloudflaredTunnelInput) async throws -> CloudflaredStatus {
        guard input.apiProxyPort > 0 else {
            throw AppError.invalidData(L10n.tr("error.cloudflared.start_api_proxy_first"))
        }

        guard let binary = CommandRunner.resolveExecutable("cloudflared") else {
            throw AppError.fileNotFound(L10n.tr("error.cloudflared.not_installed"))
        }

        if process?.isRunning == true {
            return await status()
        }

        try fileManager.createDirectory(at: paths.cloudflaredLogDirectory, withIntermediateDirectories: true)
        let logFile = paths.cloudflaredLogDirectory.appendingPathComponent("cloudflared-\(Int(Date().timeIntervalSince1970)).log", isDirectory: false)
        fileManager.createFile(atPath: logFile.path, contents: nil)

        let command = Process()
        command.executableURL = URL(fileURLWithPath: binary)

        var args = [
            "tunnel",
            "--loglevel", "info",
            "--logfile", logFile.path,
            "--no-autoupdate",
            "--url", "http://127.0.0.1:\(input.apiProxyPort)"
        ]

        if input.mode == .named, let hostname = input.hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !hostname.isEmpty {
            args.append(contentsOf: ["--hostname", hostname])
            customHostname = hostname
        } else {
            customHostname = nil
        }

        command.arguments = args

        var environment = ProcessInfo.processInfo.environment
        if input.useHTTP2 {
            environment["TUNNEL_TRANSPORT_PROTOCOL"] = "http2"
        }
        command.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        command.standardOutput = stdout
        command.standardError = stderr

        do {
            try command.run()
        } catch {
            throw AppError.io(L10n.tr("error.cloudflared.launch_failed_format", error.localizedDescription))
        }

        process = command
        mode = input.mode
        useHTTP2 = input.useHTTP2
        logPath = logFile
        lastError = nil

        for _ in 0..<20 {
            if parsePublicURL(from: logFile) != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        if process?.isRunning != true {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            lastError = errText.isEmpty ? L10n.tr("error.cloudflared.process_exited_early") : errText
            throw AppError.io(lastError ?? L10n.tr("error.cloudflared.start_failed"))
        }

        return await status()
    }

    func stop() async -> CloudflaredStatus {
        guard let process else {
            return await status()
        }

        if process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning {
                process.interrupt()
            }
        }

        self.process = nil
        self.mode = nil
        self.useHTTP2 = false
        self.customHostname = nil
        return await status()
    }

    private func parsePublicURL(from logFile: URL) -> String? {
        guard let content = try? String(contentsOf: logFile) else { return nil }

        for line in content.split(whereSeparator: { $0.isNewline }) {
            let text = String(line)
            if let range = text.range(of: "https://"), text.contains("trycloudflare.com") {
                let suffix = text[range.lowerBound...]
                let url = suffix.split(separator: " ").first.map(String.init)
                if let url {
                    return url.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }

        return nil
    }
}
