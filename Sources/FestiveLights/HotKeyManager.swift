import AppKit
import Carbon.HIToolbox

/// Registers system-wide hot keys with the Carbon Hot Key API. Unlike global
/// event taps this does not require Accessibility permission.
final class HotKeyManager {
    static let toggleShortcut = "⌥⌘L"
    static let panelShortcut = "⌥⌘P"
    static let shortcutDescription = toggleShortcut

    var onToggle: (() -> Void)?
    var onShowPanel: (() -> Void)?

    private var toggleHotKeyRef: EventHotKeyRef?
    private var panelHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    @discardableResult
    func register() -> Bool {
        guard toggleHotKeyRef == nil, panelHotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            festiveHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            NSLog("FestiveLights: could not install hot key event handler (\(installStatus))")
            return false
        }

        let signature = OSType(0x464C5453) // 'FLTS'
        let modifiers = UInt32(cmdKey | optionKey)

        let toggleID = EventHotKeyID(signature: signature, id: 1)
        let toggleStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            modifiers,
            toggleID,
            GetApplicationEventTarget(),
            0,
            &toggleHotKeyRef
        )

        let panelID = EventHotKeyID(signature: signature, id: 2)
        let panelStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            modifiers,
            panelID,
            GetApplicationEventTarget(),
            0,
            &panelHotKeyRef
        )

        if toggleStatus != noErr {
            NSLog("FestiveLights: could not register \(Self.toggleShortcut) (\(toggleStatus))")
        }
        if panelStatus != noErr {
            NSLog("FestiveLights: could not register \(Self.panelShortcut) (\(panelStatus))")
        }

        return toggleStatus == noErr || panelStatus == noErr
    }

    func unregister() {
        if let toggleHotKeyRef {
            UnregisterEventHotKey(toggleHotKeyRef)
            self.toggleHotKeyRef = nil
        }
        if let panelHotKeyRef {
            UnregisterEventHotKey(panelHotKeyRef)
            self.panelHotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    fileprivate func fireToggle() {
        DispatchQueue.main.async { [weak self] in
            self?.onToggle?()
        }
    }

    fileprivate func firePanel() {
        DispatchQueue.main.async { [weak self] in
            self?.onShowPanel?()
        }
    }

    deinit {
        unregister()
    }
}

private func festiveHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

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

    if status == noErr, hotKeyID.id == 2 {
        manager.firePanel()
    } else {
        manager.fireToggle()
    }
    return noErr
}
