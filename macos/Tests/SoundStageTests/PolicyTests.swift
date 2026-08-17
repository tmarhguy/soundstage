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
}
