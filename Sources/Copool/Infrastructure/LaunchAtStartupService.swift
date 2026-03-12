import Foundation
import ServiceManagement

final class LaunchAtStartupService: LaunchAtStartupServiceProtocol, @unchecked Sendable {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try registerMainAppIfNeeded()
        } else {
            try unregisterMainAppIfNeeded()
        }
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        let currentlyEnabled = isEnabledBySystemStatus()
        guard currentlyEnabled != enabled else { return }
        try setEnabled(enabled)
    }

    private func isEnabledBySystemStatus() -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notFound, .notRegistered:
            return false
        @unknown default:
            return false
        }
    }

    private func registerMainAppIfNeeded() throws {
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw AppError.io(L10n.tr("error.startup.enable_failed_format", error.localizedDescription))
        }
    }

    private func unregisterMainAppIfNeeded() throws {
        guard SMAppService.mainApp.status != .notRegistered else { return }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw AppError.io(L10n.tr("error.startup.disable_failed_format", error.localizedDescription))
        }
    }
}
