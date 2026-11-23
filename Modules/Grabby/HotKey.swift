import AppKit
import Carbon
import EppKit

/// 전역 단축키로 실행할 수 있는 동작.
enum HotKeyAction: String, CaseIterable {
    case captureArea, repeatLastArea, captureFullScreen, captureWindow, captureTimer, whiteboard, readCode

    var title: String {
        switch self {
        case .captureArea: return L("영역 캡처")
        case .repeatLastArea: return L("마지막 영역 다시 캡처")
        case .captureFullScreen: return L("전체 화면 캡처")
        case .captureWindow: return L("앞에 있는 창 캡처")
        case .captureTimer: return L("타이머 캡처")
        case .whiteboard: return L("화이트보드")
        case .readCode: return L("QR 코드 읽기")
        }
    }
}

/// 캡처 단축키 기본값. KeyCombo와 전역 단축키 등록은 EppKit 것을 쓴다(기능끼리 번호가 겹치지 않게).
extension KeyCombo {
    static let defaults: [String: KeyCombo] = {
        let shiftCommand = UInt32(shiftKey | cmdKey)
        return [
            HotKeyAction.captureArea.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: shiftCommand, key: "1"),
            HotKeyAction.repeatLastArea.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: shiftCommand, key: "2"),
            HotKeyAction.captureFullScreen.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: shiftCommand, key: "3"),
            HotKeyAction.captureWindow.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand, key: "4"),
            HotKeyAction.captureTimer.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: shiftCommand, key: "5"),
            // 한국어 자판에서 ₩가 찍히는 키(ANSI 자판의 `)
            HotKeyAction.whiteboard.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_Grave), modifiers: shiftCommand, key: "`"),
            HotKeyAction.readCode.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: shiftCommand, key: "6"),
        ]
    }()

    /// macOS 스크린샷 단축키와 겹치지 않는 묶음. 시스템 설정을 건드리기 싫을 때 한 번에 바꾼다.
    static let controlCommandSet: [String: KeyCombo] = defaults.mapValues {
        KeyCombo(keyCode: $0.keyCode, modifiers: UInt32(controlKey | cmdKey), key: $0.key)
    }

    /// 화이트보드 기본값이 ⌃⌘3이던 때 저장된 값.
    static let oldWhiteboardDefault = KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(controlKey | cmdKey), key: "3")
}

/// 단축키가 겹칠 수 있는 상대. macOS는 다른 앱이 쓰는 단축키를 알려 주지 않아서,
/// 알려진 캡처 앱이 켜져 있는지와 macOS 기본 스크린샷 단축키만 확인한다.
enum HotKeyConflicts {
    /// 번들 ID 앞부분 → 앱 이름
    private static let captureApps: [(prefix: String, name: String)] = [
        ("cc.ffitch.shottr", "Shottr"),
        ("pl.maketheweb.cleanshotx", "CleanShot X"),
        ("com.TechSmith.Snagit", "Snagit"),
        ("com.monosnap", "Monosnap"),
        ("com.skillbrains.lightshot", "Lightshot"),
        ("com.Snipaste", "Snipaste"),
        ("com.xnapper", "Xnapper"),
        ("com.droplr", "Droplr"),
        ("io.zappy", "Zappy"),
    ]

    /// 지금 켜져 있는 캡처 앱 이름들.
    static var runningCaptureApps: [String] {
        let ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return captureApps.filter { app in ids.contains { $0.hasPrefix(app.prefix) } }.map(\.name)
    }

    /// macOS 스크린샷 단축키 번호(com.apple.symbolichotkeys): ⇧⌘3=28, ⌃⇧⌘3=29, ⇧⌘4=30, ⌃⇧⌘4=31, ⇧⌘5=184
    private static let systemIDs: [String: Int] = ["⇧⌘3": 28, "⌃⇧⌘3": 29, "⇧⌘4": 30, "⌃⇧⌘4": 31, "⇧⌘5": 184]

    /// 그 macOS 단축키가 지금 켜져 있는지. 설정 값이 없으면 켜진 것으로 본다.
    static func isSystemShortcutEnabled(_ name: String) -> Bool {
        guard let id = systemIDs[name] else { return false }
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        guard let entry = hotkeys?[String(id)] as? [String: Any] else { return true }
        return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int).map { $0 != 0 } ?? true)
    }

    /// 지금 Grabby 단축키 중에서 켜져 있는 macOS 스크린샷 단축키와 겹치는 것들(예: ["⇧⌘3", "⇧⌘4"]).
    static func blockedBySystem(_ combos: [String: KeyCombo]) -> [String] {
        combos.values.compactMap(systemShortcut).filter(isSystemShortcutEnabled).sorted()
    }

    /// 시스템 설정 > 키보드 > 키보드 단축키를 연다(스크린샷 항목에서 끌 수 있다).
    static func openSystemShortcutSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
                    "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"]
        if let url = urls.compactMap(URL.init(string:)).first { NSWorkspace.shared.open(url) }
    }

    /// macOS 기본 스크린샷 단축키(⇧⌘3·4·5·6, ⌃⇧⌘3·4)와 같으면 그 이름.
    static func systemShortcut(_ combo: KeyCombo) -> String? {
        let shiftCommand = UInt32(shiftKey | cmdKey), withControl = UInt32(controlKey | shiftKey | cmdKey)
        let keys: [Int: String] = [kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6"]
        guard let key = keys[Int(combo.keyCode)] else { return nil }
        if combo.modifiers == shiftCommand { return "⇧⌘" + key }
        if combo.modifiers == withControl, key == "3" || key == "4" { return "⌃⇧⌘" + key }
        return nil
    }
}


/// 눌린 글자 키를 영문 소문자로 알려 준다. 한글 입력 상태(ㅁ→a)와 다른 자판 배열에서도 같은 단축키가 되도록
/// 입력된 글자를 먼저 보고, 알 수 없으면 키 위치(ANSI 자판)로 판단한다. '?'와 '/'는 '/'로 돌려준다.
enum KeyLetter {
    private static let jamo: [Character: Character] = [
        "ㅁ": "a", "ㅠ": "b", "ㅊ": "c", "ㅇ": "d", "ㄷ": "e", "ㄸ": "e", "ㄹ": "f", "ㅎ": "g", "ㅗ": "h", "ㅑ": "i", "ㅓ": "j",
        "ㅏ": "k", "ㅣ": "l", "ㅡ": "m", "ㅜ": "n", "ㅐ": "o", "ㅒ": "o", "ㅔ": "p", "ㅖ": "p", "ㅂ": "q", "ㅃ": "q", "ㄱ": "r",
        "ㄲ": "r", "ㄴ": "s", "ㅅ": "t", "ㅆ": "t", "ㅕ": "u", "ㅍ": "v", "ㅈ": "w", "ㅉ": "w", "ㅌ": "x", "ㅛ": "y", "ㅋ": "z",
    ]
    private static let codes: [Int: Character] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g",
        kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l", kVK_ANSI_M: "m", kVK_ANSI_N: "n",
        kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u",
        kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x", kVK_ANSI_Y: "y", kVK_ANSI_Z: "z", kVK_ANSI_Slash: "/",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_0: "0", kVK_ANSI_9: "9",
    ]

    static func of(_ event: NSEvent) -> Character? {
        if let c = event.charactersIgnoringModifiers?.lowercased().first {
            if c == "?" || c == "/" { return "/" }
            if c == "+" { return "=" }
            if c.isASCII, c.isLetter || c.isNumber || c == "=" || c == "-" { return c }
            if let mapped = jamo[c] { return mapped }
        }
        return codes[Int(event.keyCode)]
    }
}
