import Foundation

enum ChatGPTBaseOriginResolver {
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedOrigin: String?
    private nonisolated(unsafe) static var lastCacheTime: Date?
    private static let cacheTTL: TimeInterval = 60

    static func resolve(configPath: URL) -> String {
        cacheLock.lock()
        if let cached = cachedOrigin,
           let lastTime = lastCacheTime,
           Date().timeIntervalSince(lastTime) < cacheTTL {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = resolveFromDisk(configPath: configPath)

        cacheLock.lock()
        cachedOrigin = result
        lastCacheTime = Date()
        cacheLock.unlock()

        return result
    }

    static func invalidateCache() {
        cacheLock.lock()
        cachedOrigin = nil
        lastCacheTime = nil
        cacheLock.unlock()
    }

    private static func resolveFromDisk(configPath: URL) -> String {
        guard let raw = try? String(contentsOf: configPath, encoding: .utf8), !raw.isEmpty else {
            return "https://chatgpt.com"
        }

        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("chatgpt_base_url") else { continue }
            guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: equalIndex)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }

        return "https://chatgpt.com"
    }
}

