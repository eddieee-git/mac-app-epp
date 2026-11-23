import AppKit
import SwiftUI

/// 기능 하나를 소개하는 정보. 설정 창의 기능 목록과 메뉴에 쓴다.
public struct EppModuleInfo: Sendable, Identifiable {
    /// 주소·저장 이름에 쓰는 소문자 id (예: "keepy"). 한 번 정하면 바꾸지 않는다(설정과 데이터 위치가 여기에 묶인다).
    public let id: String
    /// 화면에 보이는 이름 (예: "Keepy")
    public let name: String
    /// 메뉴와 설정에 쓰는 SF Symbol 이름
    public let symbol: String
    public let summaryKo: String
    public let summaryEn: String

    public init(id: String, name: String, symbol: String, summaryKo: String, summaryEn: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.summaryKo = summaryKo
        self.summaryEn = summaryEn
    }

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
    /// 본체가 끝에 "<이름> 설정…"을 붙이므로 설정 항목은 넣지 않는다.
    func fillMenu(_ menu: NSMenu)

    /// 설정 창에서 이 기능을 골랐을 때 보여 줄 화면.
    func makeSettingsView() -> AnyView

    /// `epp://<id>/<명령>` 주소로 열렸을 때. 예: epp://keepy/show
    func handle(url: URL)

    /// 자체 점검(`Epp --self-test`). 실제 설정·데이터는 건드리지 않는다. 실패가 없으면 true.
    static func runSelfTest() -> Bool
}

public extension EppModule {
    func handle(url: URL) {}
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

    public init(defaults: UserDefaults, dataDirectory: URL, openSettings: @escaping () -> Void) {
        self.defaults = defaults
        self.dataDirectory = dataDirectory
        self.openSettings = openSettings
    }
}
