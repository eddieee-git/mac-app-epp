import AppKit
import Carbon
import EppKit

/// 전역 단축키로 실행할 수 있는 동작. 다른 앱을 쓰는 중에도 동작한다.
enum HotKeyAction: String, CaseIterable {
    case toggleClock, toggleTimer, stopRinging, showList

    var title: String {
        switch self {
        case .toggleClock: return L("시계 창 보이기/숨기기")
        case .toggleTimer: return L("고른 타이머 시작/일시정지")
        case .stopRinging: return L("울림 끄기")
        case .showList: return L("타이머 목록 열기")
        }
    }
}

/// 타이머 단축키 기본값. KeyCombo와 전역 단축키 등록은 EppKit 것을 쓴다(기능끼리 번호가 겹치지 않게).
extension KeyCombo {
    /// 스티커의 기본 단축키(⌃⌘N·H·M·⌫, ⌃⌥M·H)와 겹치지 않게 고른다.
    static let defaults: [String: KeyCombo] = {
        let controlOption = UInt32(controlKey | optionKey)
        return [
            HotKeyAction.toggleClock.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: controlOption, key: "C"),
            HotKeyAction.toggleTimer.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: controlOption, key: "T"),
            HotKeyAction.stopRinging.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_X), modifiers: controlOption, key: "X"),
        ]
    }()
}
