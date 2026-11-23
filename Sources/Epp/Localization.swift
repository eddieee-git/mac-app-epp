import EppKit
import Foundation

/// 본체 문구. 한국어 문구를 키로 쓰고, 언어가 한국어가 아니면 아래 사전의 영어로 바꾼다.
/// 기능 문구는 각 기능 폴더의 Localization.swift에 따로 있다.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = EppLanguage.isKorean ? key : (Localization.english[key] ?? key)
    return args.isEmpty ? format : String(format: format, arguments: args)
}

enum Localization {
    static let english: [String: String] = Dictionary(pairs, uniquingKeysWith: { first, _ in first })

    /// 자체 점검용: 두 번 들어간 키.
    static var duplicateKeys: [String] {
        var seen = Set<String>(), dupes: [String] = []
        for (key, _) in pairs where !seen.insert(key).inserted { dupes.append(key) }
        return dupes
    }

    static let pairs: [(String, String)] = [
        // 메뉴바 메뉴
        ("켠 기능이 없어요", "No features turned on"),
        ("기능 켜기…", "Turn On Features…"),
        ("%@ 설정…", "%@ Settings…"),
        ("설정…", "Settings…"),
        ("Epp 종료", "Quit Epp"),
        ("%@ 종료", "Quit %@"),

        // 앱 메뉴
        ("Epp 숨기기", "Hide Epp"),
        ("기타 숨기기", "Hide Others"),
        ("모두 보기", "Show All"),
        ("편집", "Edit"),
        ("실행 취소", "Undo"),
        ("실행 복귀", "Redo"),
        ("오려두기", "Cut"),
        ("복사", "Copy"),
        ("붙이기", "Paste"),
        ("전체 선택", "Select All"),
        ("윈도우", "Window"),
        ("창 닫기", "Close Window"),

        // 설정
        ("Epp 설정", "Epp Settings"),
        ("일반", "General"),
        ("설정 검색", "Search Settings"),
        ("검색어 지우기", "Clear search"),
        ("찾는 설정이 없어요", "No matching settings"),
        ("시작 안내", "Getting Started"),
        ("기능", "Features"),
        ("꺼짐", "Off"),
        ("%@가 꺼져 있어요. 켜면 설정이 여기에 나와요.", "%@ is off. Turn it on to see its settings here."),
        ("%@ 켜기", "Turn On %@"),
        ("단독 실행 중이라 이 기능만 켜져 있어요.", "Running on its own, so only this feature is on."),
        ("켠 기능만 실행돼요. 끈 기능은 아무 일도 하지 않고, 단축키도 등록하지 않아요.",
         "Only features you turn on run. Features that are off do nothing and register no shortcuts."),
        ("권한", "Permissions"),
        (" (필수)", " (required)"),
        (" (선택)", " (optional)"),
        ("켠 기능 중에 권한이 필요한 기능이 없어요.", "None of the features you turned on need permissions."),
        ("화면 기록은 허용한 뒤 Epp를 다시 열어야 적용돼요.", "After allowing Screen Recording, reopen Epp to apply it."),
        ("Mac은 권한을 Epp 하나에 줘요. 시스템 설정 → 개인정보 보호 및 보안에서 Epp를 켜면 모든 기능에 적용돼요.",
         "macOS gives permissions to Epp as a whole. Turn on Epp in System Settings → Privacy & Security and every feature gets it."),
        ("로그인 시 실행", "Open at login"),
        ("Dock에 아이콘 보이기", "Show icon in the Dock"),
        ("켜면 Dock에 Epp가 보이고, 메뉴 막대 왼쪽에 Epp 메뉴가 나와요. 메뉴 막대 아이콘은 그대로 있어요.",
         "When on, Epp appears in the Dock and its menus show on the left of the menu bar. The menu bar icon stays."),
        ("언어", "Language"),
        ("시스템 설정 따르기", "Follow system"),
        ("언어를 바꾸면 Epp를 다시 열어야 적용돼요.", "Reopen Epp to apply the language."),
        ("Epp 다시 열기", "Reopen Epp"),
        ("정보", "About"),
        ("버전 %@", "Version %@"),
        ("Mac을 편하게 쓰는 작은 기능 모음", "Small tools that make the Mac easier to use"),
    ]
}
