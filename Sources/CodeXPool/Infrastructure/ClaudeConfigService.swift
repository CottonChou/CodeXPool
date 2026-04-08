import Foundation

final class ClaudeConfigService: ClaudeConfigServiceProtocol, @unchecked Sendable {
    private let paths: FileSystemPaths
    private let fileManager: FileManager

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
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    func readCurrentAPIKey() -> String? {
        guard let data = try? Data(contentsOf: paths.claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any] else {
            return nil
        }
        return env["ANTHROPIC_AUTH_TOKEN"] as? String
    }
}
