import Foundation
import ServiceManagement
import SoundStageCore

/// Thin wrapper around `SMAppService.mainApp`. The OS is the source of truth;
/// nothing here is persisted in mixer `Settings`.
enum LoginItem {
    static func status(preview: Bool) -> LoginItemStatus {
        guard !preview else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .off
        case .requiresApproval: return .needsApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
