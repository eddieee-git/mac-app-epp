import AppKit
import EppKit

/// 캡처의 짧은 알림. 모양·동작은 Epp 공통 알림(`EppToast`, 화면 아래쪽 가운데)을 쓴다.
enum Toast {
    /// 바로 치운다(타이머 캡처에서 알림이 찍히지 않게).
    static func hide() {
        MainActor.assumeIsolated { EppToast.hide() }
    }

    /// `action`을 주면 알림에 버튼을 붙이고, 누를 수 있게 조금 더 오래 띄운다.
    static func show(_ message: String, image: NSImage? = nil, action: (title: String, handler: () -> Void)? = nil) {
        MainActor.assumeIsolated {
            EppToast.show(message, image: image, action: action.map { (title: $0.title, run: $0.handler) })
        }
    }
}
