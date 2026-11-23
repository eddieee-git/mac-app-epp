import AppKit
import Carbon
import EppKit

/// 전역 단축키로 실행할 수 있는 동작.
enum HotKeyAction: String, CaseIterable {
    case newNote, toggleAll, toggleCollapse, toggleCurrentCollapse, toggleCurrentHidden, trashCurrent

    var title: String {
        switch self {
        case .newNote: return L("새 스티커")
        case .toggleAll: return L("모두 표시/숨기기")
        case .toggleCollapse: return L("모두 최소화/펼치기")
        case .toggleCurrentCollapse: return L("현재 스티커 최소화/펼치기")
        case .toggleCurrentHidden: return L("현재 스티커 숨기기/표시")
        case .trashCurrent: return L("현재 스티커 삭제")
        }
    }
}

/// 스티커 단축키 기본값과 도움. KeyCombo와 전역 단축키 등록은 EppKit 것을 쓴다(기능끼리 번호가 겹치지 않게).
extension KeyCombo {
    static let defaults: [String: KeyCombo] = {
        let controlCommand = UInt32(controlKey | cmdKey), controlOption = UInt32(controlKey | optionKey)
        return [
            HotKeyAction.newNote.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: controlCommand, key: "N"),
            HotKeyAction.toggleAll.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: controlCommand, key: "H"),
            HotKeyAction.toggleCollapse.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: controlCommand, key: "M"),
            HotKeyAction.toggleCurrentCollapse.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: controlOption, key: "M"),
            HotKeyAction.toggleCurrentHidden.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: controlOption, key: "H"),
            HotKeyAction.trashCurrent.rawValue: KeyCombo(keyCode: UInt32(kVK_Delete), modifiers: controlCommand, key: "⌫"),
        ]
    }()

    /// 스티커 안 제목 변경의 기본 키.
    static let renameDefault = KeyCombo(keyCode: UInt32(kVK_F2), modifiers: 0, key: "F2")

    /// 키 입력이 이 조합과 같은지. ⇪·fn·숫자 패드 표시는 보지 않는다.
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(keyCode) else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return flags == menuModifiers
    }

    /// 따로 있던 모두 최소화·모두 펼치기 단축키를 합친 토글로 옮긴다. 둘 다 있었으면 최소화 쪽을 남긴다.
    static func migrated(_ combos: [String: KeyCombo]) -> [String: KeyCombo] {
        var combos = combos
        let old = combos.removeValue(forKey: "collapseAll")
        let oldExpand = combos.removeValue(forKey: "expandAll")
        if combos[HotKeyAction.toggleCollapse.rawValue] == nil {
            combos[HotKeyAction.toggleCollapse.rawValue] = old ?? oldExpand
        }
        return combos
    }
}
