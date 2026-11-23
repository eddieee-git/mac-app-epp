import AppKit
import UserNotifications

/// 기능이 앱 메뉴(화면 맨 위 메뉴 막대 왼쪽)에 더하는 메뉴. 본체가 자리(slot)별로 합친다.
///
/// 순서: Epp · 파일 · 편집 · 서식 · 윈도우. 같은 자리에 본체 메뉴(편집, 윈도우)가 있으면 그 아래에 이어 붙이고,
/// 같은 동작·같은 키의 항목은 한 번만 넣는다.
public struct EppMainMenu {
    public enum Slot: Int, CaseIterable, Sendable {
        case file, edit, format, window
    }

    public let slot: Slot
    public let menu: NSMenu

    public init(_ slot: Slot, _ menu: NSMenu) {
        self.slot = slot
        self.menu = menu
    }
}

/// 알림 센터. macOS는 앱마다 알림 처리기를 하나만 두므로, 본체가 받아서 보낸 기능에게 넘긴다.
/// 기능은 `post`로 보내고, 사용자가 알림을 누르면 그 기능의 `handleNotification(identifier:)`가 불린다.
public enum EppNotifications {
    /// 알림 userInfo에 넣는 보낸 기능 id
    public static let moduleKey = "eppModule"

    /// `swift run`이나 자체 점검처럼 앱 번들 없이 돌면 알림 센터를 쓸 수 없다.
    public static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// 아직 묻지 않았으면 알림 권한을 한 번 묻는다.
    public static func requestPermissionIfNeeded() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { EppPermissions.shared.refresh() } }
            }
        }
    }

    /// 알림을 보낸다. identifier가 같으면 앞의 알림을 바꾼다. 소리는 기능이 직접 낼 때가 많아 기본은 없음.
    public static func post(moduleID: String, identifier: String, title: String, body: String, sound: Bool = false) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        content.userInfo = [moduleKey: moduleID]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    public static func remove(identifiers: [String]) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
