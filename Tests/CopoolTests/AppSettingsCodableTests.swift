import XCTest
@testable import Copool

final class AppSettingsCodableTests: XCTestCase {
    func testDecodeSettingsWithMinimalFieldsSucceeds() throws {
        let json = """
        {
          "launchAtStartup": true,
          "launchCodexAfterSwitch": true,
          "autoSmartSwitch": false,
          "syncOpencodeOpenaiAuth": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "locale": "en"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.launchAtStartup, true)
        XCTAssertEqual(settings.usageProgressDisplayMode, .used)
    }

    func testDecodeSettingsWithoutUsageProgressDisplayModeDefaultsToUsed() throws {
        let json = """
        {
          "launchAtStartup": true,
          "launchCodexAfterSwitch": true,
          "autoSmartSwitch": false,
          "syncOpencodeOpenaiAuth": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "locale": "en"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.usageProgressDisplayMode, .used)
    }

    func testDecodeSettingsWithLegacyProxyFieldsIgnoredGracefully() throws {
        let json = """
        {
          "launchAtStartup": false,
          "launchCodexAfterSwitch": true,
          "autoSmartSwitch": false,
          "syncOpencodeOpenaiAuth": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "locale": "en",
          "autoStartApiProxy": true,
          "localProxyHostAPIOnly": false,
          "proxyConfiguration": {
            "preferredPortText": "4141",
            "cloudflared": {
              "enabled": false,
              "tunnelMode": "quick",
              "useHTTP2": false,
              "namedHostname": ""
            }
          },
          "remoteServers": []
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.launchAtStartup, false)
    }
}
