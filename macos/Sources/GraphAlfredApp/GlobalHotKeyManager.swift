import Carbon
import Foundation

final class GlobalHotKeyManager {
    private static let signature: OSType = 0x47414C46 // 'GALF'
    private static let hotKeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    func start(shortcut: GlobalSearchHotKey, onPress: @escaping () -> Void) {
        callback = onPress
        stop()

        guard let configuration = hotKeyConfiguration(for: shortcut) else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifierFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            stop()
        }
    }

    private func hotKeyConfiguration(for shortcut: GlobalSearchHotKey) -> (keyCode: UInt32, modifierFlags: UInt32)? {
        switch shortcut {
        case .optionSpace:
            return (UInt32(kVK_Space), UInt32(optionKey))
        case .commandOptionSpace:
            return (UInt32(kVK_Space), UInt32(optionKey | cmdKey))
        case .controlOptionSpace:
            return (UInt32(kVK_Space), UInt32(optionKey | controlKey))
        case .disabled:
            return nil
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        stop()
    }

    fileprivate func handleEvent(_ event: EventRef?) {
        guard let event else { return }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == Self.signature,
              hotKeyID.id == Self.hotKeyID
        else {
            return
        }

        callback?()
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else {
        return noErr
    }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleEvent(eventRef)

    return noErr
}
