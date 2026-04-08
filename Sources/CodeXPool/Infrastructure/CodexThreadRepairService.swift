import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

#if os(macOS)
final class CodexThreadRepairService: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    struct RepairResult {
        var normalizedThreads: Int = 0
        var threadStateUpdates: Int = 0
        var sessionMetaUpdates: Int = 0
        var sessionIndexUpdates: Int = 0
        var backupDir: String?
    }

    func repairThreadVisibility(targetProvider: String = "openai", targetModel: String? = nil) -> RepairResult {
        var result = RepairResult()
        let home = fileManager.homeDirectoryForCurrentUser
        let codexHome = home.appendingPathComponent(".codex")
        let stateDB = codexHome.appendingPathComponent("state_5.sqlite")
        let configPath = codexHome.appendingPathComponent("config.toml")
        let appSupport = home.appendingPathComponent("Library/Application Support/Codex")
        let threadStatePath = appSupport.appendingPathComponent("backups/current/thread_state.json")
        let sessionIndexPath = appSupport.appendingPathComponent("backups/current/session_index.jsonl")

        let model = targetModel ?? readModelFromConfig(at: configPath)

        guard fileManager.fileExists(atPath: stateDB.path) else {
            return result
        }

        let backupDir = createBackup(stateDB: stateDB, threadStatePath: threadStatePath, sessionIndexPath: sessionIndexPath, appSupport: appSupport)
        result.backupDir = backupDir?.path

        let (normalizedCount, rolloutPaths) = normalizeThreadsInDB(
            dbPath: stateDB.path,
            targetProvider: targetProvider,
            targetModel: model
        )
        result.normalizedThreads = normalizedCount

        if fileManager.fileExists(atPath: threadStatePath.path) {
            result.threadStateUpdates = updateThreadStateJSON(
                path: threadStatePath,
                targetProvider: targetProvider,
                targetModel: model
            )
        }

        for rolloutPath in rolloutPaths {
            let url = URL(fileURLWithPath: rolloutPath)
            let updates = updateJSONLMetadata(path: url, targetProvider: targetProvider, targetModel: model)
            result.sessionMetaUpdates += updates

            if let rel = relativePath(of: url, relativeTo: codexHome) {
                let mirror = appSupport.appendingPathComponent("backups/current").appendingPathComponent(rel)
                result.sessionMetaUpdates += updateJSONLMetadata(path: mirror, targetProvider: targetProvider, targetModel: model)
            }
        }

        if fileManager.fileExists(atPath: sessionIndexPath.path) {
            result.sessionIndexUpdates = updateSessionIndex(
                path: sessionIndexPath,
                targetProvider: targetProvider,
                targetModel: model
            )
        }

        return result
    }

    private func readModelFromConfig(at configPath: URL) -> String {
        guard let text = try? String(contentsOf: configPath, encoding: .utf8) else {
            return "gpt-5.4"
        }
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model") && !trimmed.hasPrefix("model_") && trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard key == "model" else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return "gpt-5.4"
    }

    private func createBackup(stateDB: URL, threadStatePath: URL, sessionIndexPath: URL, appSupport: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        let ts = formatter.string(from: Date())
        let backupDir = appSupport.appendingPathComponent("backups/provider-visibility-fix-\(ts)")
        do {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: stateDB.path) {
                try fileManager.copyItem(at: stateDB, to: backupDir.appendingPathComponent("state_5.sqlite"))
            }
            if fileManager.fileExists(atPath: threadStatePath.path) {
                try fileManager.copyItem(at: threadStatePath, to: backupDir.appendingPathComponent("thread_state.json"))
            }
            if fileManager.fileExists(atPath: sessionIndexPath.path) {
                try fileManager.copyItem(at: sessionIndexPath, to: backupDir.appendingPathComponent("session_index.jsonl"))
            }
            return backupDir
        } catch {
            return nil
        }
    }

    private func normalizeThreadsInDB(dbPath: String, targetProvider: String, targetModel: String) -> (Int, [String]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            return (0, [])
        }
        defer { sqlite3_close(db) }

        var rolloutPaths: [String] = []

        let selectSQL = """
            SELECT id, rollout_path FROM threads
            WHERE archived_at IS NULL
              AND (model_provider != ? OR COALESCE(model, '') != ?)
        """
        var selectStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(selectStmt, 1, (targetProvider as NSString).utf8String, -1, nil)
            sqlite3_bind_text(selectStmt, 2, (targetModel as NSString).utf8String, -1, nil)
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(selectStmt, 1) {
                    rolloutPaths.append(String(cString: pathPtr))
                }
            }
        }
        sqlite3_finalize(selectStmt)

        let updateSQL = """
            UPDATE threads
            SET model_provider = ?, model = ?
            WHERE archived_at IS NULL
              AND (model_provider != ? OR COALESCE(model, '') != ?)
        """
        var updateStmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStmt, 1, (targetProvider as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStmt, 2, (targetModel as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStmt, 3, (targetProvider as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStmt, 4, (targetModel as NSString).utf8String, -1, nil)
            if sqlite3_step(updateStmt) == SQLITE_DONE {
                count = Int(sqlite3_changes(db))
            }
        }
        sqlite3_finalize(updateStmt)

        return (count, rolloutPaths)
    }

    private func updateThreadStateJSON(path: URL, targetProvider: String, targetModel: String) -> Int {
        guard let data = try? Data(contentsOf: path),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var threads = root["threads"] as? [[String: Any]] else {
            return 0
        }

        var updates = 0
        for i in threads.indices {
            let archived = threads[i]["archived"] as? Int ?? 0
            guard archived == 0 else { continue }

            if let currentProvider = threads[i]["model_provider"] as? String, currentProvider != targetProvider {
                threads[i]["model_provider"] = targetProvider
                updates += 1
            }
            if let currentModel = threads[i]["model"] as? String, currentModel != targetModel {
                threads[i]["model"] = targetModel
                updates += 1
            }
        }

        if updates > 0 {
            root["threads"] = threads
            if let newData = try? JSONSerialization.data(withJSONObject: root, options: []) {
                try? newData.write(to: path, options: .atomic)
            }
        }
        return updates
    }

    private func updateJSONLMetadata(path: URL, targetProvider: String, targetModel: String) -> Int {
        guard fileManager.fileExists(atPath: path.path),
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return 0
        }

        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var totalUpdates = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                newLines.append(line)
                continue
            }

            guard let lineData = trimmed.data(using: .utf8),
                  var obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                newLines.append(line)
                continue
            }

            guard var payload = obj["payload"] as? [String: Any] else {
                newLines.append(line)
                continue
            }

            var changed = false
            let type = obj["type"] as? String

            if type == "session_meta" {
                if let mp = payload["model_provider"] as? String, mp != targetProvider {
                    payload["model_provider"] = targetProvider
                    totalUpdates += 1
                    changed = true
                }
                if payload["model"] != nil, let m = payload["model"] as? String, m != targetModel {
                    payload["model"] = targetModel
                    totalUpdates += 1
                    changed = true
                }
            } else if type == "turn_context" {
                if payload["model"] != nil, let m = payload["model"] as? String, m != targetModel {
                    payload["model"] = targetModel
                    totalUpdates += 1
                    changed = true
                }
            }

            if changed {
                obj["payload"] = payload
                if let jsonData = try? JSONSerialization.data(withJSONObject: obj, options: []),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    newLines.append(jsonStr)
                } else {
                    newLines.append(line)
                }
            } else {
                newLines.append(line)
            }
        }

        if totalUpdates > 0 {
            let result = newLines.joined(separator: "\n")
            try? result.write(to: path, atomically: true, encoding: .utf8)
        }
        return totalUpdates
    }

    private func updateSessionIndex(path: URL, targetProvider: String, targetModel: String) -> Int {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return 0 }

        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var totalUpdates = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  var obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                newLines.append(trimmed)
                continue
            }

            let archived = obj["archived"] as? Int ?? (obj["archived"] as? Bool == true ? 1 : 0)
            if archived == 0 {
                if let mp = obj["model_provider"] as? String, mp != targetProvider {
                    obj["model_provider"] = targetProvider
                    totalUpdates += 1
                }
                if let m = obj["model"] as? String, m != targetModel {
                    obj["model"] = targetModel
                    totalUpdates += 1
                }
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: obj, options: []),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                newLines.append(jsonStr)
            } else {
                newLines.append(trimmed)
            }
        }

        if totalUpdates > 0, !newLines.isEmpty {
            let result = newLines.joined(separator: "\n") + "\n"
            try? result.write(to: path, atomically: true, encoding: .utf8)
        }
        return totalUpdates
    }

    private func relativePath(of url: URL, relativeTo base: URL) -> String? {
        let urlPath = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path + "/"
        guard urlPath.hasPrefix(basePath) else { return nil }
        return String(urlPath.dropFirst(basePath.count))
    }
}
#endif
