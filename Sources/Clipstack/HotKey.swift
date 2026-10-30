import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon.
///
/// Carbon is the only API that still registers a global hotkey without
/// Accessibility permission, which is why every app in this category uses it.
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private let identifier: UInt32
    private var reference: EventHotKeyRef?

    /// - Parameters:
    ///   - keyCode: a `kVK_` virtual key code.
    ///   - modifiers: Carbon modifier mask (`cmdKey`, `shiftKey`, ...).
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        identifier = Self.nextID
        Self.nextID += 1
        Self.actions[identifier] = action
        Self.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5053), id: identifier) // 'CLPS'
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &reference)
        guard status == noErr else {
            Self.actions[identifier] = nil
            return nil
        }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        HotKey.actions[identifier] = nil
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, let action = HotKey.actions[hotKeyID.id] else { return noErr }
            DispatchQueue.main.async(execute: action)
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
