import AppKit
import EppKit

/// 스티커 기능을 처음 켰을 때 띄우는 안내 스티커. (사용법 링크는 옛 단독 앱의 공개 문서)
/// 처음 설치했을 때 띄우는 안내 스티커. 처음 1분 안에 필요한 것만 담고, 자세한 내용은 사용법 페이지로 보낸다.
enum WelcomeNote {
    static let guideURL = URL(string: "https://github.com/eddieee-git/mac-app-floaty/blob/main/docs/guide.md")!
    static let englishGuideURL = URL(string: "https://github.com/eddieee-git/mac-app-floaty/blob/main/docs/guide.en.md")!

    /// 단축키는 지금 설정된 값으로 보여 준다. 지정되지 않았으면 그 줄을 메뉴 이름으로 대신한다.
    static func make(hotKeys: [String: KeyCombo]) -> (title: String, body: NSAttributedString) {
        let newNote = hotKeys[HotKeyAction.newNote.rawValue]?.displayText
        let toggleAll = hotKeys[HotKeyAction.toggleAll.rawValue]?.displayText
        let isKorean = EppLanguage.isKorean

        let lines: [String]
        let heading: String
        let link: String
        let footer: String
        if isKorean {
            heading = "스티커 시작하기"
            lines = [
                "메뉴바의 Epp 아이콘 → 스티커에서 모든 기능을 열어요",
                [newNote.map { "\($0) 새 스티커" }, toggleAll.map { "\($0) 모두 숨기기/보이기" }]
                    .compactMap { $0 }.joined(separator: "   "),
                "제목을 누르면 이름을 바꾸고, 더블클릭하면 접히고, 끌면 옮겨져요",
                "스티커에서 ⌘F 또는 메뉴의 스티커 관리: 모든 메모 목록, 검색, 휴지통",
                "Epp 설정 → 스티커에서 단축키·색을 바꿔요",
            ]
            link = "자세한 사용법 →"
            footer = "다 읽었으면 위쪽의 휴지통 버튼으로 지우세요."
        } else {
            heading = "Getting Started with Stickies"
            lines = [
                "Open everything from the Epp icon in the menu bar → Stickies",
                [newNote.map { "\($0) New sticky" }, toggleAll.map { "\($0) Hide/show all" }]
                    .compactMap { $0 }.joined(separator: "   "),
                "Click the title to rename it, double-click to collapse, drag to move",
                "⌘F in a sticky or Manage Stickies in the menu: list, search, Trash",
                "Change shortcuts and colors in Epp Settings → Stickies",
            ]
            link = "Full guide →"
            footer = "When you're done, delete this with the trash button at the top."
        }

        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]
        let body = NSMutableAttributedString()
        for line in lines where !line.isEmpty {
            body.append(NSAttributedString(string: "• " + line + "\n", attributes: base))
        }
        body.append(NSAttributedString(string: "\n", attributes: base))
        body.append(NSAttributedString(string: link, attributes: base.merging([.link: isKorean ? guideURL : englishGuideURL]) { $1 }))
        body.append(NSAttributedString(string: "\n", attributes: base))
        body.append(NSAttributedString(string: footer, attributes: base.merging([.foregroundColor: NSColor.darkGray]) { $1 }))
        return (heading, body)
    }
}
