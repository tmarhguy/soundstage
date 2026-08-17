import Foundation
import Carbon

/// System-wide Control–Option–Slash (⌃⌥/) via Carbon `RegisterEventHotKey`.
final class GlobalHotKey {
    static let keyCode = UInt32(kVK_ANSI_Slash) // 0x2C
    static let modifiers = UInt32(controlKey | optionKey)
    private static let signature: OSType = 0x5353_7467 // 'SStg'
    private static let hotKeyID: UInt32 = 1

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    func install(handler: @escaping () -> Void) {
        uninstall()
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let box = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr,
                      hkID.signature == GlobalHotKey.signature,
                      hkID.id == GlobalHotKey.hotKeyID else {
                    return noErr
                }
                DispatchQueue.main.async { box.handler?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            uninstall()
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let reg = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if reg != noErr {
            uninstall()
        }
    }

    func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        handler = nil
    }

    deinit {
        uninstall()
    }
}
