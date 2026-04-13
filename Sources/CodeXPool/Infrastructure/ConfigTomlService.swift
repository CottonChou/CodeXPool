import Foundation

final class ConfigTomlService: ConfigTomlServiceProtocol, @unchecked Sendable {
    private let paths: FileSystemPaths
    private let fileManager: FileManager

    init(paths: FileSystemPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func readModelProvider() -> String? {
        guard let raw = try? String(contentsOf: paths.codexConfigPath, encoding: .utf8),
              !raw.isEmpty else {
            return nil
        }

        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model_provider") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    func writeForAPIKeyMode(profile: APIKeyProfile) throws {
        let parentDirectory = paths.codexConfigPath.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let reservedProviders: Set<String> = ["openai", "anthropic", "google", "amazon-bedrock", "azure"]
        let rawProvider = profile.providerLabel
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let candidate = rawProvider.isEmpty ? "openai-custom" : rawProvider
        let providerName = reservedProviders.contains(candidate) ? "\(candidate)-custom" : candidate

        let (topLevel, sections) = existingPreservedLines(removingProviderSection: providerName)

        var lines: [String] = []

        lines.append("model_provider = \"\(providerName)\"")
        lines.append("model = \"\(profile.model)\"")
        if let effort = profile.reasoningEffort, !effort.isEmpty {
            lines.append("model_reasoning_effort = \"\(effort)\"")
        }
        lines.append("disable_response_storage = false")
        lines.append("preferred_auth_method = \"apikey\"")

        if !topLevel.isEmpty {
            lines.append("")
            lines.append(contentsOf: topLevel)
        }

        lines.append("")
        lines.append("[model_providers.\(providerName)]")
        lines.append("name = \"\(providerName)\"")
        lines.append("base_url = \"\(profile.baseURL)\"")
        lines.append("wire_api = \"\(profile.wireAPI)\"")

        if !sections.isEmpty {
            lines.append("")
            lines.append(contentsOf: sections)
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: paths.codexConfigPath, atomically: true, encoding: .utf8)

        try writeAuthJSON(apiKey: profile.apiKey)
    }

    func writeForChatGPTMode() throws {
        let parentDirectory = paths.codexConfigPath.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let (topLevel, sections) = existingPreservedLines(removingProviderSection: nil)

        var lines: [String] = []
        lines.append("model_provider = \"openai\"")

        if !topLevel.isEmpty {
            lines.append("")
            lines.append(contentsOf: topLevel)
        }

        let nonProviderSections = stripAllModelProviderSections(sections)
        if !nonProviderSections.isEmpty {
            lines.append("")
            lines.append(contentsOf: nonProviderSections)
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: paths.codexConfigPath, atomically: true, encoding: .utf8)
    }

    private func stripAllModelProviderSections(_ sectionLines: [String]) -> [String] {
        var result: [String] = []
        var skipping = false
        for line in sectionLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                skipping = trimmed.hasPrefix("[model_providers.")
            }
            if !skipping {
                result.append(line)
            }
        }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }
        return result
    }

    private func writeAuthJSON(apiKey: String) throws {
        let authJSON: [String: String] = ["OPENAI_API_KEY": apiKey]
        let data = try JSONSerialization.data(
            withJSONObject: authJSON,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: paths.codexAuthPath, options: .atomic)
    }

    private func existingPreservedLines(
        removingProviderSection: String?
    ) -> (topLevel: [String], sections: [String]) {
        guard let raw = try? String(contentsOf: paths.codexConfigPath, encoding: .utf8) else {
            return ([], [])
        }

        let managedTopLevelKeys: Set<String> = [
            "model_provider",
            "model",
            "model_reasoning_effort",
            "reasoning_effort",
            "disable_response_storage",
            "preferred_auth_method"
        ]

        let allLines = raw.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map(String.init)

        var topLevel: [String] = []
        var sections: [String] = []
        var inSection = false
        var skipSection = false

        for line in allLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                inSection = true
                if trimmed.hasPrefix("[model_providers.") {
                    if let sectionName = removingProviderSection,
                       trimmed == "[model_providers.\(sectionName)]" {
                        skipSection = true
                        continue
                    }
                }
                skipSection = false
            }

            if skipSection { continue }

            if inSection {
                sections.append(line)
            } else {
                let isManaged = managedTopLevelKeys.contains { key in
                    trimmed.hasPrefix(key) && trimmed.contains("=")
                }
                if !isManaged {
                    topLevel.append(line)
                }
            }
        }

        while topLevel.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            topLevel.removeLast()
        }
        while sections.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            sections.removeLast()
        }

        return (topLevel, sections)
    }
}
