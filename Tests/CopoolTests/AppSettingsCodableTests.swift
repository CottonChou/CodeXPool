import XCTest
@testable import Copool

final class AppSettingsCodableTests: XCTestCase {
    func testDecodeLegacySettingsWithoutAutoSmartSwitchUsesDefault() throws {
        let json = """
        {
          "launchAtStartup": true,
          "trayUsageDisplayMode": "remaining",
          "launchCodexAfterSwitch": true,
          "syncOpencodeOpenaiAuth": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "autoStartApiProxy": true,
          "remoteServers": [],
          "locale": "en"
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.autoSmartSwitch, false)
        XCTAssertEqual(decoded.autoStartApiProxy, true)
        XCTAssertEqual(decoded.localProxyHostAPIOnly, false)
        XCTAssertEqual(decoded.proxyConfiguration.cloudflared.enabled, false)
        XCTAssertEqual(decoded.proxyConfiguration, .defaultValue)
        XCTAssertEqual(decoded.locale, AppLocale.english.identifier)
    }
}
