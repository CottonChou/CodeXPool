import Foundation

final class ClaudeConfigService: ClaudeConfigServiceProtocol, @unchecked Sendable {
    private let paths: FileSystemPaths
    private let fileManager: FileManager

    private let cacheLock = NSLock()
    private var cachedEnv: [String: Any]?
    private var lastCacheTime: Date?
    private static let cacheTTL: TimeInterval = 30

    init(paths: FileSystemPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func writeForAPIKeyMode(profile: ClaudeAPIKeyProfile) throws {
        let settingsURL = paths.claudeSettingsPath
        let parentDir = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var settings: [String: Any]
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        } else {
            settings = [:]
        }

        var env = (settings["env"] as? [String: Any]) ?? [:]
        env["ANTHROPIC_AUTH_TOKEN"] = profile.apiKey
        env["ANTHROPIC_BASE_URL"] = profile.baseURL
        settings["env"] = env

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
        invalidateCache()
    }

    func readCurrentAPIKey() -> String? {
        readCachedEnvValue("ANTHROPIC_AUTH_TOKEN")
    }

    func readCurrentBaseURL() -> String? {
        readCachedEnvValue("ANTHROPIC_BASE_URL")
    }

    private func readCachedEnvValue(_ key: String) -> String? {
        cacheLock.lock()
        if let env = cachedEnv,
           let lastTime = lastCacheTime,
           Date().timeIntervalSince(lastTime) < Self.cacheTTL {
            cacheLock.unlock()
            return env[key] as? String
        }
        cacheLock.unlock()

        let env = readEnvFromDisk()

        cacheLock.lock()
        cachedEnv = env
        lastCacheTime = Date()
        cacheLock.unlock()

        return env?[key] as? String
    }

    private func readEnvFromDisk() -> [String: Any]? {
        guard let data = try? Data(contentsOf: paths.claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any] else {
            return nil
        }
        return env
    }

    private func invalidateCache() {
        cacheLock.lock()
        cachedEnv = nil
        lastCacheTime = nil
        cacheLock.unlock()
    }
}
