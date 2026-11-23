import AppKit
import EppKit

/// 스티커를 지운 자리에 잠깐 뜨는 "되돌리기" 알림. 모양·동작은 Epp 공통 알림(`EppToast`).
@MainActor
final class UndoToast {
    private static let duration: TimeInterval = 6

    /// 되돌릴 수 있는 것은 마지막으로 지운 스티커 하나다. 새 알림이 오면 바뀐다.
    func show(message: String, near frame: NSRect, action: @escaping () -> Void) {
        EppToast.show(message, symbol: "trash", action: (title: L("되돌리기"), run: action),
                      place: .below(frame), duration: Self.duration)
    }

    func hide() { EppToast.hide() }
}
