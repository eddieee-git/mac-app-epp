import AppKit
import SwiftUI

/// 기능 하나를 소개하는 정보. 설정 창의 기능 목록과 메뉴에 쓴다.
public struct EppModuleInfo: Sendable, Identifiable {
    /// 주소·저장 이름에 쓰는 소문자 id (예: "keepy"). 한 번 정하면 바꾸지 않는다(설정과 데이터 위치가 여기에 묶인다).
    public let id: String
    /// 저장 이름: 데이터 폴더(~/Library/Application Support/Epp/<이름>)와 로그에 쓴다. 옛 단독 앱 이름(예: "Keepy"). 바꾸지 않는다.
    public let storageName: String
    /// 화면에 보이는 기능 이름. 앱 이름이 아니라 하는 일로 짓는다(예: "클립보드" / "Clipboard").
    public let nameKo: String
    public let nameEn: String
    /// 메뉴와 설정에 쓰는 SF Symbol 이름
    public let symbol: String
    public let summaryKo: String
    public let summaryEn: String

    public init(id: String, storageName: String, nameKo: String, nameEn: String, symbol: String,
                summaryKo: String, summaryEn: String) {
        self.id = id
        self.storageName = storageName
        self.nameKo = nameKo
        self.nameEn = nameEn
        self.symbol = symbol
        self.summaryKo = summaryKo
        self.summaryEn = summaryEn
    }

    public var name: String { EppLanguage.isKorean ? nameKo : nameEn }
    public var summary: String { EppLanguage.isKorean ? summaryKo : summaryEn }
}

/// Epp 안의 기능 하나가 지키는 약속.
///
/// 본체는 기능을 켤 때 `init(context:)` → `start()`, 끌 때 `stop()`을 부르고 그 객체를 버린다.
/// 꺼진 기능은 객체가 없으므로 아무것도 하지 않는다(타이머·단축키·창 없음).
@MainActor
public protocol EppModule: AnyObject {
    static var info: EppModuleInfo { get }

    init(context: EppContext)

    /// 감시·단축키 등을 시작한다.
    func start()
    /// 시작한 것을 모두 멈추고 저장할 것을 저장한다. Epp를 끝낼 때도 불린다.
    func stop()

    /// 메뉴바 메뉴에 들어갈 항목을 채운다. 메뉴를 열 때마다 새로 부른다.
    /// 순서: 주 동작(열기) → 기능 고유 항목. 본체가 끝에 "시작 안내"와 "<이름> 설정…"을 붙이므로 넣지 않는다.
    func fillMenu(_ menu: NSMenu)

    /// 설정 탭. 틀(머리·탭·검색)은 본체가 `EppSettingsPage`로 그린다. 순서: 일반 · (고유 탭) · 단축키.
    func settingsTabs() -> [EppSettingsTab]

    /// 설정 맨 위 "시작하기" 상자에 넣을 내용(보통 `EppStepList`). 메뉴의 "시작 안내"로 다시 연다.
    func makeGettingStarted() -> AnyView?

    /// `epp://<id>/<명령>` 주소로 열렸을 때. 예: epp://keepy/show
    func handle(url: URL)

    /// 앱 메뉴(메뉴 막대 왼쪽 파일·편집·서식·윈도우)에 더할 메뉴. 기능을 켜고 끌 때마다 본체가 다시 모은다.
    func mainMenus() -> [EppMainMenu]

    /// 이 기능이 보낸 알림(`EppNotifications.post`)을 사용자가 눌렀을 때.
    func handleNotification(identifier: String)

    /// Epp를 끝내도 되는지. 저장하지 못한 내용이 있으면 물어보고 false를 돌려줄 수 있다.
    func shouldQuit() -> Bool

    /// 지금 등록한 전역 단축키(어디서나 동작하는 키). Epp 일반 → 단축키에 모아 보여 주고 겹치면 알린다.
    func globalShortcuts() -> [EppShortcutInfo]

    /// 이 기능이 쓰는 macOS 권한. 권한은 Epp 일반 → 권한 한 곳에서 다루고, 기능 설정에는 권한 칸을 두지 않는다.
    static var permissionNeeds: [EppPermissionNeed] { get }

    /// 자체 점검(`Epp --self-test`). 실제 설정·데이터는 건드리지 않는다. 실패가 없으면 true.
    static func runSelfTest() -> Bool
}

public extension EppModule {
    func handle(url: URL) {}
    func makeGettingStarted() -> AnyView? { nil }
    static var permissionNeeds: [EppPermissionNeed] { [] }
    func globalShortcuts() -> [EppShortcutInfo] { [] }
    func mainMenus() -> [EppMainMenu] { [] }
    func handleNotification(identifier: String) {}
    func shouldQuit() -> Bool { true }
}

/// 본체가 기능에 넘겨주는 것: 그 기능만 쓰는 설정 저장소와 데이터 폴더, 본체 동작.
@MainActor
public final class EppContext {
    /// 이 기능만 쓰는 UserDefaults. 다른 기능·본체와 키가 겹치지 않는다.
    public let defaults: UserDefaults
    /// 이 기능만 쓰는 데이터 폴더 (~/Library/Application Support/Epp/<이름>)
    public let dataDirectory: URL
    /// 설정 창을 열고 이 기능을 보여 준다.
    public let openSettings: () -> Void
    /// 시작하기 상자를 다시 보이게 하고 설정 창에서 이 기능을 연다(권한이 없어 동작을 못 할 때 등).
    public var showGettingStarted: () -> Void {
        { [defaults = UserDefaults.standard, id = moduleID, openSettings] in
            defaults.set(false, forKey: EppSettingsKeys.gettingStartedHidden(id))
            defaults.set("general", forKey: EppSettingsKeys.tab(id))
            openSettings()
        }
    }
    /// 이 기능의 id
    public let moduleID: String
    /// Epp 설정 → 일반(권한 칸이 있는 쪽)을 연다.
    public let openPermissions: () -> Void
    /// Epp 본체의 메뉴바 아이콘. 메뉴바 아이콘을 숨기는 기능(Peeky)이 이것까지 숨기지 않게 한다.
    public let hostStatusItems: () -> [NSStatusItem]
    /// 진단 로그 같은 파일 이름 앞에 붙일 앱 이름 ("Epp" 또는 "Epp Dev")
    public let appName: String

    public init(moduleID: String, defaults: UserDefaults, dataDirectory: URL, openSettings: @escaping () -> Void,
                openPermissions: @escaping () -> Void = {},
                hostStatusItems: @escaping () -> [NSStatusItem] = { [] }, appName: String = "Epp") {
        self.moduleID = moduleID
        self.openPermissions = openPermissions
        self.defaults = defaults
        self.dataDirectory = dataDirectory
        self.openSettings = openSettings
        self.hostStatusItems = hostStatusItems
        self.appName = appName
    }
}
