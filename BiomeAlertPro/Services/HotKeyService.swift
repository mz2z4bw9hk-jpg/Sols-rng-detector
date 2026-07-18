import Carbon.HIToolbox
import Foundation

/// Registers system-wide hotkeys via the Carbon Hot Key API, which works from
/// a sandboxed app and does not require Accessibility permission. Fixed
/// bindings keep the surface small:
///   • ⌥⌘J — join the last detected Roblox link
///   • ⌥⌘P — pause / resume monitoring
///
/// Carbon hot-key events are delivered on the main run loop, so the callbacks
/// hop to the main actor before touching app state.
final class HotKeyService: @unchecked Sendable {
    enum Action: UInt32 {
        case joinLast = 1
        case togglePause = 2
        case clickNewest = 3
    }

    /// Invoked on the main actor when a hotkey fires.
    var onJoinLast: (@Sendable () -> Void)?
    var onTogglePause: (@Sendable () -> Void)?
    var onClickNewest: (@Sendable () -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var installed = false

    // Carbon modifier + key-code constants.
    private static let cmd: UInt32 = UInt32(cmdKey)
    private static let option: UInt32 = UInt32(optionKey)
    private static let keyJ: UInt32 = 0x26 // kVK_ANSI_J
    private static let keyP: UInt32 = 0x23 // kVK_ANSI_P
    private static let keyK: UInt32 = 0x28 // kVK_ANSI_K
    private static let signature = fourCharCode("BAPx")

    /// Human-readable descriptions for the UI.
    static let joinLastDescription = "⌥⌘J"
    static let togglePauseDescription = "⌥⌘P"
    static let clickNewestDescription = "⌥⌘K"

    func register() {
        guard !installed else { return }

        var handlerRef: EventHandlerRef?
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                service.dispatch(id: hotKeyID.id)
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handlerRef)
        eventHandler = handlerRef

        registerHotKey(id: Action.joinLast.rawValue, keyCode: Self.keyJ, modifiers: Self.cmd | Self.option)
        registerHotKey(id: Action.togglePause.rawValue, keyCode: Self.keyP, modifiers: Self.cmd | Self.option)
        registerHotKey(id: Action.clickNewest.rawValue, keyCode: Self.keyK, modifiers: Self.cmd | Self.option)
        installed = true
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        installed = false
    }

    // MARK: - Private

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }

    private func dispatch(id: UInt32) {
        switch Action(rawValue: id) {
        case .joinLast: onJoinLast?()
        case .togglePause: onTogglePause?()
        case .clickNewest: onClickNewest?()
        case .none: break
        }
    }
}

/// Packs a four-character string into an OSType (Carbon signature).
private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value & 0xFF)
    }
    return result
}
