import AppKit
import Carbon

/// 키와 보조키 조합. `key`는 화면에 보여 줄 키 이름이다.
public struct KeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    /// Carbon 형식(cmdKey, optionKey 등)
    public var modifiers: UInt32
    public var key: String

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// 전역 단축키로 쓸 수 없는 입력이면 nil. 기능 키 말고는 ⌘, ⌃, ⌥ 중 하나가 있어야 한다.
    public init?(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }

        let code = Int(event.keyCode)
        guard let name = Self.specialKeys[code] ?? Self.asciiName(of: event.keyCode) else { return nil }
        let isFunctionKey = name.hasPrefix("F") && name.count > 1
        guard isFunctionKey || carbon & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(code), modifiers: UInt32(carbon), key: name)
    }

    /// 한글 입력 상태에서도 영문 키 이름을 얻으려고 ASCII 자판으로 변환한다.
    private static func asciiName(of keyCode: UInt16) -> String? {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: length).uppercased()
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }

    public var displayText: String {
        let mods = Int(modifiers)
        return (mods & controlKey != 0 ? "⌃" : "") + (mods & optionKey != 0 ? "⌥" : "")
            + (mods & shiftKey != 0 ? "⇧" : "") + (mods & cmdKey != 0 ? "⌘" : "") + (key == "`" ? "₩" : key)
    }

    /// 메뉴 항목에 표시할 키. 특수 키는 메뉴에 그대로 쓸 수 없어 표시하지 않는다.
    public var menuKey: String { Self.specialKeys[Int(keyCode)] == nil ? key.lowercased() : "" }

    public var menuModifiers: NSEvent.ModifierFlags {
        let mods = Int(modifiers)
        var flags: NSEvent.ModifierFlags = []
        if mods & cmdKey != 0 { flags.insert(.command) }
        if mods & optionKey != 0 { flags.insert(.option) }
        if mods & controlKey != 0 { flags.insert(.control) }
        if mods & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }
}

/// Carbon RegisterEventHotKey 기반 전역 단축키. 손쉬운 사용 권한이 필요 없다.
///
/// 여러 기능이 한 앱 안에서 단축키를 등록하므로 번호는 여기서 자동으로 나눠 주고,
/// 키 이벤트 처리기는 하나만 두고 번호로 나눠 보낸다.
/// 객체가 사라지면 등록도 풀린다.
@MainActor
public final class HotKey {
    private static let signature = OSType(0x4550_5050) // 'EPPP'
    private static var nextID: UInt32 = 1
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    /// 지금 등록돼 있는 단축키 수(점검용: 기능을 껐는데 남아 있으면 안 된다)
    public static var registeredCount: Int { actions.count }

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// 시스템이 등록을 거부하면 nil. 다른 앱과 겹치는 조합은 대부분 거부되지 않고 등록되며, 먼저 등록한 앱이 받는다.
    public init?(combo: KeyCombo, action: @escaping () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
        Self.actions[id] = action
    }

    /// 키 코드와 Carbon 보조 키로 바로 등록한다(화면에 보여 줄 키 이름이 필요 없을 때).
    public convenience init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.init(combo: KeyCombo(keyCode: keyCode, modifiers: modifiers, key: ""), action: action)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        let id = id
        MainActor.assumeIsolated { _ = Self.actions.removeValue(forKey: id) }
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            let id = pressed.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKey.actions[id]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
