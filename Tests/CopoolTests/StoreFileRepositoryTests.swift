import XCTest
@testable import Copool

final class StoreFileRepositoryTests: XCTestCase {
    func testExtractFirstJSONObjectDataCanRecoverTrailingGarbage() throws {
        let malformed = "{\"version\":1,\"accounts\":[],\"settings\":{\"launchAtStartup\":false,\"trayUsageDisplayMode\":\"remaining\",\"launchCodexAfterSwitch\":true,\"syncOpencodeOpenaiAuth\":false,\"restartEditorsOnSwitch\":false,\"restartEditorTargets\":[],\"autoStartApiProxy\":false,\"remoteServers\":[],\"locale\":\"zh-CN\"}} trailing text".data(using: .utf8)!

        let recovered = StoreFileRepository.extractFirstJSONObjectData(from: malformed)

        XCTAssertNotNil(recovered)
        let decoder = JSONDecoder()
        XCTAssertNoThrow(try decoder.decode(AccountsStore.self, from: recovered!))
    }

    func testLoadStoreRecoversWhenTrailingGarbageExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storePath = tempDir.appendingPathComponent("accounts.json")
        let raw = "{\"version\":1,\"accounts\":[],\"settings\":{\"launchAtStartup\":false,\"trayUsageDisplayMode\":\"remaining\",\"launchCodexAfterSwitch\":true,\"syncOpencodeOpenaiAuth\":false,\"restartEditorsOnSwitch\":false,\"restartEditorTargets\":[],\"autoStartApiProxy\":false,\"remoteServers\":[],\"locale\":\"zh-CN\"}}\nINVALID".data(using: .utf8)!
        try raw.write(to: storePath)

        let paths = FileSystemPaths(
            applicationSupportDirectory: tempDir,
            accountStorePath: storePath,
            codexAuthPath: tempDir.appendingPathComponent("auth.json"),
            codexConfigPath: tempDir.appendingPathComponent("config.toml"),
            proxyDaemonDataDirectory: tempDir.appendingPathComponent("proxyd", isDirectory: true),
            proxyDaemonKeyPath: tempDir.appendingPathComponent("proxyd/api-proxy.key", isDirectory: false),
            cloudflaredLogDirectory: tempDir.appendingPathComponent("cloudflared-logs", isDirectory: true)
        )

        let repository = StoreFileRepository(paths: paths)
        let store = try repository.loadStore()

        XCTAssertEqual(store.version, 1)
        XCTAssertEqual(store.accounts.count, 0)
    }
}
