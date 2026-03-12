import Foundation

enum L10n {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var localeOverrideIdentifier: String?

    private static var rootBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func setLocale(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        localeOverrideIdentifier = AppLocale.resolve(identifier).identifier
    }

    private static var bundle: Bundle {
        lock.lock()
        let override = localeOverrideIdentifier
        lock.unlock()

        guard let override,
              let path = rootBundle.path(forResource: override, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return rootBundle
        }
        return localizedBundle
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
