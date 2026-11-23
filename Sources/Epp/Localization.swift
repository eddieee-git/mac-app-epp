import EppKit
import Foundation

enum Localization {
    static let translations = EppTranslations(pairs)
    static var english: [String: String] { translations.english }
    /// 자체 점검용: 두 번 들어간 키.
    static var duplicateKeys: [String] { translations.duplicateKeys }

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
        ("찾는 설정이 없어요", "No matching settings"),
        ("시작 안내", "Getting Started"),
        ("기능", "Features"),
        ("꺼짐", "Off"),
        ("%@가 꺼져 있어요. 켜면 설정이 여기에 나와요.", "%@ is off. Turn it on to see its settings here."),
        ("%@ 켜기", "Turn On %@"),
        ("단독 실행 중이라 이 기능만 켜져 있어요.", "Running on its own, so only this feature is on."),
        ("Epp에 오신 걸 환영해요", "Welcome to Epp"),
        ("빠른 검색…", "Quick Search…"),
        ("설정 파일", "Settings File"),
        ("설정 옮기기", "Move Settings"),
        ("설정 내보내기", "Export Settings"),
        ("설정 가져오기", "Import Settings"),
        ("설정 내보내기…", "Export Settings…"),
        ("설정 가져오기…", "Import Settings…"),
        ("켠 기능·단축키·테마 같은 설정을 파일 하나로 옮겨요(새 Mac 등). 클립보드 기록·스티커·캡처 같은 내용은 들어가지 않아요. 내용은 위의 데이터 폴더를 복사해요.",
         "Move settings such as enabled features, shortcuts, and themes in a single file (e.g. to a new Mac). Content like clipboard history, stickies, and captures isn't included — copy the data folder above for that."),
        ("Epp 설정 파일이 아니에요", "This Isn't an Epp Settings File"),
        ("설정 → 일반 → 설정 옮기기의 \"설정 내보내기…\"로 만든 파일을 골라 주세요.",
         "Choose a file made with \"Export Settings…\" in Settings → General → Move Settings."),
        ("이 설정으로 바꿀까요?", "Replace Your Settings?"),
        ("파일에 든 설정으로 덮어쓰고 Epp를 다시 열어요. 클립보드 기록·스티커·캡처 같은 내용은 그대로예요.",
         "Epp will overwrite its settings with the ones in the file and reopen. Content like clipboard history, stickies, and captures stays as it is."),
        ("바꾸고 다시 열기", "Replace and Reopen"),
        ("취소", "Cancel"),
        ("빠른 검색", "Quick Search"),
        ("빠른 검색 열기", "Open Quick Search"),
        ("켠 기능의 내용(클립보드 기록, 스티커, 캡처 속 글자, 타이머·알람)을 한 번에 찾아요. 잠근 스티커는 찾지 않아요.",
         "Search everything in the features you turned on — clipboard history, stickies, text in captures, timers and alarms. Locked stickies are never searched."),
        ("클립보드·스티커·캡처·타이머에서 찾기", "Search clipboard, stickies, captures, timers"),
        ("찾을 말을 입력하세요. ↑↓로 고르고 ↩로 열어요. 클립보드 항목은 앞의 앱에 붙여 넣어요.",
         "Type to search. Use ↑↓ to choose and ↩ to open. Clipboard items paste into the app in front."),
        ("찾는 내용이 없어요.", "No results."),
        ("아래에서 쓸 기능을 켜세요. 여러 개를 한꺼번에 켜도 돼요. 켠 기능은 왼쪽 목록에 나오고, 처음 열면 시작하기가 하나씩 안내해요.",
         "Turn on the features you want below — as many as you like. Features you turn on appear in the list on the left, and Getting Started walks you through each one."),
        ("설정 열기", "Open Settings"),
        ("%@ 설정과 시작하기를 열어요.", "Open %@ settings and Getting Started."),
        ("켠 기능만 실행돼요. 끈 기능은 아무 일도 하지 않고, 단축키도 등록하지 않아요.",
         "Only features you turn on run. Features that are off do nothing and register no shortcuts."),
        ("권한", "Permissions"),
        (" (필수)", " (required)"),
        (" (선택)", " (optional)"),
        ("켠 기능 중에 권한이 필요한 기능이 없어요.", "None of the features you turned on need permissions."),
        ("화면 기록은 허용한 뒤 Epp를 다시 열어야 적용돼요.", "After allowing Screen Recording, reopen Epp to apply it."),
        ("Mac은 권한을 Epp 하나에 줘요. 시스템 설정 → 개인정보 보호 및 보안에서 Epp를 켜면 모든 기능에 적용돼요.",
         "macOS gives permissions to Epp as a whole. Turn on Epp in System Settings → Privacy & Security and every feature gets it."),
        ("\"%@\" (%@) — %@의 \"%@\"와 같은 키예요. 먼저 등록한 기능만 동작해요.",
         "\"%@\" (%@) uses the same keys as \"%4$@\" in %3$@. Only the feature that registered first gets it."),
        ("업데이트", "Updates"),
        ("문제 해결", "Troubleshooting"),
        ("진단 로그 남기기", "Keep a diagnostic log"),
        ("로그 파일 보기", "Show Log File"),
        ("데이터 폴더", "Data folder"),
        ("Finder에서 보기", "Show in Finder"),
        ("진단 로그는 권한·동작 문제를 찾을 때만 켜요. 모든 기능이 한 파일(~/Library/Logs)에 적고, 복사한 내용 같은 개인 내용은 적지 않아요. 끄면 파일을 지워요.",
         "Turn on the diagnostic log only to track down permission or behavior problems. Every feature writes to one file (~/Library/Logs), never personal content such as what you copied. Turning it off deletes the file."),
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

/// 화면 문구. 한국어 문구를 그대로 넘기면 Epp 언어로 돌려준다. `%@`, `%ld` 등은 args로 채운다.
func L(_ korean: String, _ args: CVarArg...) -> String {
    Localization.translations.text(korean, args)
}
