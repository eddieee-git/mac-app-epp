import AppKit
import EppKit

/// 알람이 울릴 때 macOS 알림 센터에도 남긴다. 화면을 보고 있지 않았어도 나중에 알림 목록에서 확인할 수 있다.
/// 처음 알람을 걸 때 한 번 권한을 묻는다. 알림은 Epp 본체가 받아 스티커 기능에 넘긴다(FloatyModule.handleNotification).
enum AlarmNotifier {
    static let moduleID = "floaty"
    static var isAvailable: Bool { EppNotifications.isAvailable }

    static func requestPermissionIfNeeded() {
        EppNotifications.requestPermissionIfNeeded()
    }

    /// 잠긴 스티커는 제목만 쓰고, 제목이 없으면 이름을 드러내지 않는다. identifier는 스티커 id.
    static func post(noteID: UUID, title: String, body: String) {
        // 소리는 기능이 직접 낸다.
        EppNotifications.post(moduleID: moduleID, identifier: noteID.uuidString, title: title, body: body)
    }
}
