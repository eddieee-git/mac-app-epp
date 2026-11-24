import EppKit
import Foundation

enum Localization {
    static let translations = EppTranslations(pairs)
    static var english: [String: String] { translations.english }
    /// 자체 점검용: 두 번 들어간 키.
    static var duplicateKeys: [String] { translations.duplicateKeys }

    static let pairs: [(String, String)] = [
        ("클립보드", "Clipboard"),
        // Epp 공통 설정 틀
        ("손쉬운 사용 권한 허용하기 (Epp 설정 → 일반 → 권한)", "Allow Accessibility (Epp Settings → General → Permissions)"),
        ("권한 열기", "Open Permissions"),
        ("평소처럼 복사하기. Epp가 기록해 둬요.", "Copy as usual. Epp keeps a record."),
        ("%@로 기록을 열고 ↩로 붙여 넣기", "Open the history with %@ and press Return to paste"),
        ("메뉴", "the menu"),
        ("⌘1~9로 바로 고르고, ⌘P로 자주 쓰는 항목을 맨 위에 고정해요. 비밀번호 관리자에서 복사한 내용은 기록하지 않아요.",
         "Pick with ⌘1–9 and pin items you use often with ⌘P. Copies from password managers are never recorded."),
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

        // 기록 창·알림
        ("복사", "Copy"),
        ("서식 없이 복사", "Copy as Plain Text"),
        ("복사했어요", "Copied"),

        // 기록 창
        ("클립보드 기록 검색", "Search clipboard history"),
        ("검색어 지우기", "Clear search"),
        ("찾는 항목이 없어요", "No matches"),
        ("붙여 넣기", "Paste"),
        ("서식 없이 붙여 넣기", "Paste as Plain Text"),
        ("서식 없이", "Plain text"),
        ("고정", "Pin"),
        ("스티커로 만들기", "Make Sticky"),
        ("1Password, Bitwarden, Dashlane, LastPass, KeePassXC, Proton Pass 같은 비밀번호 관리자는 목록에 없어도 늘 기록하지 않아요.", "Password managers such as 1Password, Bitwarden, Dashlane, LastPass, KeePassXC, and Proton Pass are never recorded, even if they aren't in the list."),
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

        // 설정
        ("일반", "General"),
        ("제외 앱", "Excluded Apps"),
        ("단축키", "Shortcuts"),
        ("기록", "History"),
        ("보관할 항목 수", "Items to keep"),
        ("오래된 기록 지우기", "Delete old history"),
        ("지우지 않음", "Never"),
        ("%ld일 지나면", "After %ld days"),
        ("기록은 암호화해서 이 Mac에만 저장해요. 고정한 항목은 날짜가 지나도 지우지 않아요.",
         "History is encrypted and stays on this Mac. Pinned items are never deleted by age."),
        ("기록 창 위치", "History window position"),
        ("마우스 포인터 위치", "At the pointer"),
        ("화면 가운데", "Center of the screen"),
        ("모든 기록 지우기…", "Clear All History…"),
        ("모든 기록을 지울까요?", "Clear all history?"),
        ("모두 지우기", "Clear All"),
        ("고정한 항목까지 모두 지워져요. 되돌릴 수 없어요.", "Pinned items are cleared too. This can't be undone."),
        ("고르면 바로 붙여 넣기", "Paste right after picking"),
        ("끄면 고른 항목을 클립보드에 복사만 하고, ⌘V는 직접 눌러요.", "When off, Epp only copies the item you pick, and you press ⌘V yourself."),
        ("이 앱에서 복사한 내용은 기록하지 않아요", "Copies from these apps are not recorded"),
        ("한 줄에 번들 ID 하나씩 적어요. 비밀번호 관리자가 숨김 표시를 붙여 복사한 내용은 앱과 상관없이 기록하지 않아요.",
         "One bundle ID per line. Copies that password managers mark as concealed are never recorded, whatever the app."),
        ("실행 중인 앱에서 더하기", "Add from running apps"),
        ("기본값으로", "Restore Defaults"),
        ("전역 단축키", "Global shortcut"),
        ("기록 창 안에서", "In the history window"),
        ("%@이(가) 켜져 있어요. 같은 단축키를 쓰면 먼저 등록한 앱이 키를 받으니, 겹치지 않게 바꿔 주세요.",
         "%@ is running. If it uses the same shortcut, the app that registered first gets the key, so pick a different one."),
        ("항목 고르기", "Choose an item"),
        ("그 번호 항목 바로 붙여 넣기", "Paste that item right away"),
        ("고정 / 고정 풀기", "Pin / Unpin"),
        ("삭제 되돌리기", "Undo delete"),
        ("검색어 지우기 / 닫기", "Clear search / Close"),
    ]
}

/// 화면 문구. 한국어 문구를 그대로 넘기면 Epp 언어로 돌려준다. `%@`, `%ld` 등은 args로 채운다.
func L(_ korean: String, _ args: CVarArg...) -> String {
    Localization.translations.text(korean, args)
}
