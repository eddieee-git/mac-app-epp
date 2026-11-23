import EppKit
import Foundation

/// 한국어 문구를 키로 쓴다. 언어가 한국어가 아니면 아래 사전의 영어로 바꾼다.
/// 새 문구를 쓰면 `pairs`에 영어를 더한다. 빠진 번역은 scripts/test.sh가, 같은 키가 두 번 들어간 것은 자체 점검이 알려 준다.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Localization.isKorean ? key : (Localization.english[key] ?? key)
    return args.isEmpty ? format : String(format: format, arguments: args)
}

enum Localization {
    /// Epp 설정 → 일반 → 언어를 따른다.
    static var isKorean: Bool { EppLanguage.isKorean }

    static let english: [String: String] = Dictionary(pairs, uniquingKeysWith: { first, _ in first })

    /// 자체 점검용: 두 번 들어간 키.
    static var duplicateKeys: [String] {
        var seen = Set<String>(), dupes: [String] = []
        for (key, _) in pairs where !seen.insert(key).inserted { dupes.append(key) }
        return dupes
    }

    static let pairs: [(String, String)] = [
        // 메뉴바 메뉴
        ("클립보드 기록 열기", "Open Clipboard History"),
        ("최근 항목", "Recent"),
        ("아직 복사한 항목이 없어요", "Nothing copied yet"),
        ("이미지 %@", "Image %@"),
        ("기록 일시 정지", "Pause Recording"),
        ("기록 지우기…", "Clear History…"),
        ("기록을 지울까요?", "Clear the history?"),
        ("고정한 항목은 남겨요. 지운 기록은 되돌릴 수 없어요.", "Pinned items are kept. Cleared history can't be restored."),
        ("지우기", "Clear"),
        ("취소", "Cancel"),
        ("시작 안내", "Getting Started"),

        // 기록 창·알림
        ("복사", "Copy"),
        ("서식 없이 복사", "Copy as Plain Text"),
        ("복사했어요", "Copied"),
        ("• 메뉴바에 Epp 아이콘이 안 보이면 시스템 설정 → 메뉴 막대에서 Epp를 켜 주세요.", "• If the Epp icon is missing from the menu bar, turn on Epp in System Settings → Menu Bar."),

        // 기록 창
        ("클립보드 기록 검색", "Search clipboard history"),
        ("검색어 지우기", "Clear search"),
        ("찾는 항목이 없어요", "No matches"),
        ("붙여 넣기", "Paste"),
        ("서식 없이 붙여 넣기", "Paste as Plain Text"),
        ("서식 없이", "Plain text"),
        ("고정", "Pin"),
        ("고정 풀기", "Unpin"),
        ("삭제", "Delete"),
        ("%ld개", "%ld items"),
        ("삭제했어요 · ⌘Z 되돌리기", "Deleted · ⌘Z to undo"),
        ("되돌렸어요", "Restored"),
        ("이미지", "Image"),
        ("%ld자", "%ld characters"),
        ("%ld자 · %ld줄", "%ld characters · %ld lines"),
        ("파일", "File"),
        ("파일 %ld개", "%ld files"),

        // 시작 안내
        ("Keepy 시작 안내", "Getting Started with Keepy"),
        ("Keepy에 오신 걸 환영해요", "Welcome to Keepy"),
        ("복사한 내용을 모아 두었다가 언제든 다시 붙여 넣는 메뉴바 앱이에요.", "A menu bar app that keeps what you copy so you can paste it again anytime."),
        ("1. 손쉬운 사용 권한", "1. Accessibility permission"),
        ("켜져 있어요. 고른 항목을 앞에 있던 앱에 바로 붙여 넣어요.", "It's on. Keepy pastes the item you pick right into the app you were using."),
        ("고른 항목을 바로 붙여 넣으려면 필요해요. 없어도 클립보드에 복사는 돼요. 업데이트한 뒤라면 이미 켜져 있어도 한 번 껐다 켜야 할 수 있어요.",
         "Needed to paste the item you pick right away. Without it, Keepy still copies it to the clipboard. After an update you may need to turn it off and on again."),
        ("허용하기", "Allow"),
        ("2. 단축키", "2. Shortcut"),
        ("없음", "None"),
        ("3. 쓰는 방법", "3. How to use"),
        ("• 평소처럼 복사하면 Keepy가 기록해 둬요.", "• Copy as usual and Keepy keeps a record."),
        ("• 단축키로 기록을 열고, 입력해서 찾고, ↩로 붙여 넣어요.", "• Open the history with the shortcut, type to search, and press Return to paste."),
        ("• ⌘1~9로 바로 고르고, ⌘P로 자주 쓰는 항목을 맨 위에 고정해요.", "• Pick with ⌘1–9, and pin items you use often to the top with ⌘P."),
        ("• 비밀번호 관리자에서 복사한 내용은 기록하지 않아요.", "• Copies from password managers are never recorded."),
        ("다음부터 열지 않기", "Don't show again"),
        ("설정 열기", "Open Settings"),
        ("시작하기", "Get Started"),

        // 설정
        ("설정", "Settings"),
        ("일반", "General"),
        ("제외 앱", "Excluded Apps"),
        ("단축키", "Shortcuts"),
        ("기록", "History"),
        ("보관할 항목 수", "Items to keep"),
        ("기록 창 위치", "History window position"),
        ("마우스 포인터 위치", "At the pointer"),
        ("화면 가운데", "Center of the screen"),
        ("저장 위치", "Storage"),
        ("Finder에서 보기", "Show in Finder"),
        ("모든 기록 지우기…", "Clear All History…"),
        ("모든 기록을 지울까요?", "Clear all history?"),
        ("모두 지우기", "Clear All"),
        ("고정한 항목까지 모두 지워져요. 되돌릴 수 없어요.", "Pinned items are cleared too. This can't be undone."),
        ("고르면 바로 붙여 넣기", "Paste right after picking"),
        ("손쉬운 사용 권한 허용됨", "Accessibility permission allowed"),
        ("손쉬운 사용 권한이 필요해요", "Accessibility permission needed"),
        ("끄면 고른 항목을 클립보드에 복사만 하고, ⌘V는 직접 눌러요.", "When off, Keepy only copies the item you pick, and you press ⌘V yourself."),
        ("이 앱에서 복사한 내용은 기록하지 않아요", "Copies from these apps are not recorded"),
        ("한 줄에 번들 ID 하나씩 적어요. 비밀번호 관리자가 숨김 표시를 붙여 복사한 내용은 앱과 상관없이 기록하지 않아요.",
         "One bundle ID per line. Copies that password managers mark as concealed are never recorded, whatever the app."),
        ("실행 중인 앱에서 더하기", "Add from running apps"),
        ("기본값으로", "Restore Defaults"),
        ("전역 단축키", "Global shortcut"),
        ("기록 창 안에서", "In the history window"),
        ("%@이(가) 켜져 있어요. 같은 단축키를 쓰면 먼저 등록한 앱이 키를 받으니, 겹치지 않게 바꿔 주세요.",
         "%@ is running. If it uses the same shortcut, the app that registered first gets the key, so pick a different one."),
        ("등록하지 못함", "Couldn't register"),
        ("키를 누르세요", "Press keys"),
        ("단축키 지우기", "Clear shortcut"),
        ("다른 앱과 겹치면 먼저 등록한 앱이 키를 받아요. esc로 입력 취소.", "If another app uses the same keys, the one that registered first gets them. Press esc to cancel."),
        ("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.", "Press it together with ⌘, ⌃ or ⌥."),
        ("항목 고르기", "Choose an item"),
        ("그 번호 항목 바로 붙여 넣기", "Paste that item right away"),
        ("고정 / 고정 풀기", "Pin / Unpin"),
        ("삭제 되돌리기", "Undo delete"),
        ("검색어 지우기 / 닫기", "Clear search / Close"),
    ]
}
