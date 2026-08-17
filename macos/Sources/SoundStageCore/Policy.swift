import Foundation

/// Persisted mixer state. Kept here so it can round-trip in tests without AppKit.
public struct Settings: Codable, Equatable {
    public var enabled: [String: Bool] = [:]
    public var gain: [String: Float] = [:]
    public var delayMs: [String: Float] = [:]
    public var mute: [String: Bool] = [:]
    public var master: Float = 1
    public var masterUid: String? = nil
    public var wasRunning: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent([String: Bool].self, forKey: .enabled) ?? [:]
        gain = try c.decodeIfPresent([String: Float].self, forKey: .gain) ?? [:]
        delayMs = try c.decodeIfPresent([String: Float].self, forKey: .delayMs) ?? [:]
        mute = try c.decodeIfPresent([String: Bool].self, forKey: .mute) ?? [:]
        master = try c.decodeIfPresent(Float.self, forKey: .master) ?? 1
        masterUid = try c.decodeIfPresent(String.self, forKey: .masterUid)
        wasRunning = try c.decodeIfPresent(Bool.self, forKey: .wasRunning) ?? false
    }
}

/// Output device used for enable/clock policy. Mirrors the engine's `AudioDevice` fields
/// tests care about without pulling in Core Audio.
public struct DeviceRef: Equatable {
    public let uid: String
    public let transport: String

    public init(uid: String, transport: String) {
        self.uid = uid
        self.transport = transport
    }
}

/// Explicit setting wins; otherwise on — except HDMI/DP, which often break
/// private aggregates on macOS 26 (IO never starts). Those are opt-in.
public func isDeviceEnabled(uid: String, transport: String, enabled: [String: Bool]) -> Bool {
    if let explicit = enabled[uid] { return explicit }
    if transport == "hdmi" || transport == "displayport" {
        return false
    }
    return true
}

public func isDeviceEnabled(_ device: DeviceRef, enabled: [String: Bool]) -> Bool {
    isDeviceEnabled(uid: device.uid, transport: device.transport, enabled: enabled)
}

/// Gatekeeper App Translocation: quarantined apps opened from Downloads/Desktop
/// run from a random read-only path.
public func isAppTranslocationPath(_ path: String) -> Bool {
    path.contains("/AppTranslocation/")
}

/// Mute zeros the device; otherwise stored gain, defaulting to 1.
public func effectiveGain(uid: String, gain: [String: Float], mute: [String: Bool]) -> Float {
    (mute[uid] ?? false) ? 0 : (gain[uid] ?? 1)
}

/// Prefer an explicit clock if still enabled; else builtin > hdmi/dp/usb > first.
public func preferredClockUid(enabled: [DeviceRef], current: String?) -> String? {
    if let uid = current, enabled.contains(where: { $0.uid == uid }) {
        return uid
    }
    let pick = enabled.first { $0.transport == "builtin" }
        ?? enabled.first { ["hdmi", "displayport", "usb"].contains($0.transport) }
        ?? enabled.first
    return pick?.uid
}
