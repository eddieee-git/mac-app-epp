import AppKit
import EppKit

/// 붙여 넣지 않고 복사만 했을 때 잠깐 띄우는 "복사했어요" 알림. 모양은 Epp 공통 알림(`EppToast`).
/// 메뉴바 아이콘은 가려져 있을 수 있어서(노치, 메뉴바 정리 앱) 기록 창이 있던 자리에 띄운다.
@MainActor
enum CopiedToast {
    /// center: 알림을 띄울 화면 위치(기록 창이 있던 자리의 가운데)
    static func show(at center: NSPoint) {
        EppToast.show(L("복사했어요"), symbol: "checkmark.circle.fill", place: .center(center), duration: 0.9)
    }
}
