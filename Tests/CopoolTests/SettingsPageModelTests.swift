import XCTest
@testable import Copool

@MainActor
final class SettingsPageModelTests: XCTestCase {
    func testQuitAppInvokesInjectedAction() {
        var didQuit = false
        let model = SettingsPageModel(
            settingsCoordinator: SettingsCoordinator(
                storeRepository: InMemorySettingsStoreRepository(),
                launchAtStartupService: SettingsStubLaunchAtStartupService()
            ),
            editorAppService: SettingsStubEditorAppService(),
            onQuitRequested: {
                didQuit = true
            }
        )

        model.quitApp()

        XCTAssertTrue(didQuit)
    }
}

private final class InMemorySettingsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store = AccountsStore()

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

private struct SettingsStubLaunchAtStartupService: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) throws {
        _ = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        _ = enabled
    }
}

private struct SettingsStubEditorAppService: EditorAppServiceProtocol {
    func listInstalledApps() -> [InstalledEditorApp] {
        []
    }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        (targets, nil)
    }
}
