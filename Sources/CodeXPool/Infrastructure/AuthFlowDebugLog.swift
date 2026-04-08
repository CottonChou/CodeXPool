import Foundation

enum AuthFlowDebugLog {
    private static let lock = NSLock()

    static func write(_ category: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        guard let appSupportBase = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return
        }

        let directory = appSupportBase.appendingPathComponent("CodexToolsSwift", isDirectory: true)
        let fileURL = directory.appendingPathComponent("auth-flow-debug.log", isDirectory: false)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(category)] \(message)\n"

        if !fileManager.fileExists(atPath: fileURL.path) {
            try? line.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }

        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {}
    }
}
