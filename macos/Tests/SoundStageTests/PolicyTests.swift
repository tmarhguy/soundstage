import XCTest
@testable import SoundStageCore

final class TranslocationTests: XCTestCase {
    func testDetectsAppTranslocationPath() {
        XCTAssertTrue(isAppTranslocationPath("/private/var/folders/xx/AppTranslocation/ABC/d/SoundStage.app"))
        XCTAssertFalse(isAppTranslocationPath("/Applications/SoundStage.app"))
        XCTAssertFalse(isAppTranslocationPath("/Users/me/Downloads/SoundStage.app"))
    }
}

final class GainTests: XCTestCase {
    func testDefaultGainIsOne() {
        XCTAssertEqual(effectiveGain(uid: "a", gain: [:], mute: [:]), 1)
    }

    func testStoredGain() {
        XCTAssertEqual(effectiveGain(uid: "a", gain: ["a": 0.5], mute: [:]), 0.5)
    }

    func testMuteZerosGain() {
        XCTAssertEqual(effectiveGain(uid: "a", gain: ["a": 0.8], mute: ["a": true]), 0)
    }
}

final class ClockTests: XCTestCase {
    func testPrefersBuiltinOverHdmiAndBluetooth() {
        let devices = [
            DeviceRef(uid: "bt", transport: "bluetooth"),
            DeviceRef(uid: "hdmi", transport: "hdmi"),
            DeviceRef(uid: "builtin", transport: "builtin"),
        ]
        XCTAssertEqual(preferredClockUid(enabled: devices, current: nil), "builtin")
    }

    func testKeepsExplicitClockIfStillEnabled() {
        let devices = [
            DeviceRef(uid: "usb", transport: "usb"),
            DeviceRef(uid: "builtin", transport: "builtin"),
        ]
        XCTAssertEqual(preferredClockUid(enabled: devices, current: "usb"), "usb")
    }

    func testDropsExplicitClockIfNotEnabled() {
        let devices = [DeviceRef(uid: "builtin", transport: "builtin")]
        XCTAssertEqual(preferredClockUid(enabled: devices, current: "gone"), "builtin")
    }

    func testEmptyList() {
        XCTAssertNil(preferredClockUid(enabled: [], current: "x"))
    }
}

final class SettingsCodableTests: XCTestCase {
    func testRoundTrip() throws {
        var s = Settings()
        s.enabled = ["hdmi-1": true]
        s.gain = ["a": 0.4]
        s.delayMs = ["a": 180]
        s.mute = ["a": true]
        s.master = 0.9
        s.masterUid = "builtin"
        s.wasRunning = true

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testEmptyJSONObjectDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, Settings())
        XCTAssertEqual(decoded.master, 1)
        XCTAssertFalse(decoded.wasRunning)
    }

    func testEncodedSettingsHasNoLoginItemField() throws {
        var s = Settings()
        s.wasRunning = true
        s.masterUid = "builtin"
        let data = try JSONEncoder().encode(s)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("openAtLogin"))
        XCTAssertFalse(json.contains("loginItem"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["openAtLogin"])
        XCTAssertEqual(Set(object.keys), ["enabled", "gain", "delayMs", "mute", "master", "masterUid", "wasRunning"])
    }
}

final class LoginItemPresentationTests: XCTestCase {
    func testEnabledIsOnAndInteractive() {
        let p = loginItemPresentation(status: .enabled, translocated: false)
        XCTAssertTrue(p.isOn)
        XCTAssertTrue(p.isInteractive)
        XCTAssertEqual(p.caption, loginItemResumeCaption)
        XCTAssertFalse(p.showsSystemSettingsLink)
    }

    func testOffIsOffAndInteractive() {
        let p = loginItemPresentation(status: .off, translocated: false)
        XCTAssertFalse(p.isOn)
        XCTAssertTrue(p.isInteractive)
        XCTAssertEqual(p.caption, loginItemResumeCaption)
        XCTAssertFalse(p.showsSystemSettingsLink)
    }

    func testNeedsApprovalShowsSystemSettingsLink() {
        let p = loginItemPresentation(status: .needsApproval, translocated: false)
        XCTAssertTrue(p.isOn)
        XCTAssertFalse(p.isInteractive)
        XCTAssertEqual(p.caption, loginItemNeedsApprovalCaption)
        XCTAssertTrue(p.showsSystemSettingsLink)
    }

    func testUnavailableIsDisabled() {
        let p = loginItemPresentation(status: .unavailable, translocated: false)
        XCTAssertFalse(p.isOn)
        XCTAssertFalse(p.isInteractive)
        XCTAssertEqual(p.caption, loginItemUnavailableCaption)
        XCTAssertFalse(p.showsSystemSettingsLink)
    }

    func testTranslocatedOverridesEnabled() {
        let p = loginItemPresentation(status: .enabled, translocated: true)
        XCTAssertFalse(p.isOn)
        XCTAssertFalse(p.isInteractive)
        XCTAssertEqual(p.caption, loginItemTranslocatedCaption)
        XCTAssertFalse(p.showsSystemSettingsLink)
    }

    func testTranslocatedOverridesNeedsApproval() {
        let p = loginItemPresentation(status: .needsApproval, translocated: true)
        XCTAssertFalse(p.isOn)
        XCTAssertFalse(p.isInteractive)
        XCTAssertEqual(p.caption, loginItemTranslocatedCaption)
        XCTAssertFalse(p.showsSystemSettingsLink)
    }

    func testTranslocatedOverridesOffAndUnavailable() {
        for status in [LoginItemStatus.off, .unavailable] {
            let p = loginItemPresentation(status: status, translocated: true)
            XCTAssertEqual(p, loginItemPresentation(status: .enabled, translocated: true))
        }
    }
}
