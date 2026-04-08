import Foundation
import OSLog

final class AuthBackupService: AuthBackupServiceProtocol, @unchecked Sendable {
    private let paths: FileSystemPaths
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "CodeXPool", category: "AuthBackup")

    init(paths: FileSystemPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func backupCurrentAuthFiles() throws {
        try fileManager.createDirectory(
            at: paths.codexBackupsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Self.timestampString()

        if fileManager.fileExists(atPath: paths.codexAuthPath.path) {
            let backupName = "auth-\(timestamp).json"
            let destination = paths.codexBackupsDirectory
                .appendingPathComponent(backupName, isDirectory: false)
            try fileManager.copyItem(at: paths.codexAuthPath, to: destination)
            logger.log("Backed up auth.json to \(backupName, privacy: .public)")
        }

        if fileManager.fileExists(atPath: paths.codexConfigPath.path) {
            let backupName = "config-\(timestamp).toml"
            let destination = paths.codexBackupsDirectory
                .appendingPathComponent(backupName, isDirectory: false)
            try fileManager.copyItem(at: paths.codexConfigPath, to: destination)
            logger.log("Backed up config.toml to \(backupName, privacy: .public)")
        }

        pruneOldBackups()
    }

    private func pruneOldBackups() {
        let maxBackups = 20
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.codexBackupsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = entries.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return aDate > bDate
        }

        if sorted.count > maxBackups {
            for entry in sorted.dropFirst(maxBackups) {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
