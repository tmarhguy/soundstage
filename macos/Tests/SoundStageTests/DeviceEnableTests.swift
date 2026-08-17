import XCTest
@testable import SoundStageCore

final class DeviceEnableTests: XCTestCase {
    func testBuiltinAndBluetoothDefaultOn() {
        XCTAssertTrue(isDeviceEnabled(uid: "BuiltInSpeakerDevice", transport: "builtin", enabled: [:]))
        XCTAssertTrue(isDeviceEnabled(uid: "bt", transport: "bluetooth", enabled: [:]))
        XCTAssertTrue(isDeviceEnabled(uid: "usb", transport: "usb", enabled: [:]))
    }

    func testHdmiAndDisplayPortDefaultOff() {
        XCTAssertFalse(isDeviceEnabled(uid: "hdmi-1", transport: "hdmi", enabled: [:]))
        XCTAssertFalse(isDeviceEnabled(uid: "dp-1", transport: "displayport", enabled: [:]))
    }

    func testExplicitSettingOverridesDefault() {
        XCTAssertTrue(isDeviceEnabled(uid: "hdmi-1", transport: "hdmi", enabled: ["hdmi-1": true]))
        XCTAssertFalse(isDeviceEnabled(uid: "BuiltInSpeakerDevice", transport: "builtin", enabled: ["BuiltInSpeakerDevice": false]))
    }
}
