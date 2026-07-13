import AppKit
import Carbon.HIToolbox

/// Carbon の RegisterEventHotKey を使ったグローバルホットキー。
/// 指定した組み合わせのときだけ発火するので、全キー入力を監視する必要がない
/// (キーロガー的な監視を避けられる)。
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    // C コールバックはコンテキストを持てないため、id で action を引く
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    /// - Parameters:
    ///   - keyCode: 仮想キーコード(例: V = 9)
    ///   - modifiers: Carbon 修飾フラグ(cmdKey / optionKey / controlKey / shiftKey)
    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        Self.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: 0x5152_5343 /* 'QRSC' */, id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let action = GlobalHotKey.actions[hkID.id] {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.actions[id] = nil
    }
}
