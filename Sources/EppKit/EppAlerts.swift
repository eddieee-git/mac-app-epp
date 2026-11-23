import Foundation

/// 기능이 알리는 "이때 울려 주세요" 하나(예: 스티커 알람).
public struct EppAlert: Equatable, Sendable {
    /// 울릴 때마다 달라야 한다(시각이 바뀌면 새 id). 끝에 `|<초>`를 붙이면 오래된 기록 정리에 쓴다.
    public let id: String
    public let title: String
    public let date: Date
    /// 알린 기능 id
    public let source: String

    public init(id: String, title: String, date: Date, source: String) {
        self.id = id
        self.title = title
        self.date = date
        self.source = source
    }
}

/// Epp 알람 한곳: 여러 기능의 알람을 한 가지 방식으로 울린다.
///
/// - 알람이 있는 기능(스티커)은 `publish`로 다가오는 알람을 올린다.
/// - 울리는 기능(타이머)이 켜져 있으면 `hasRinger`가 참이고, 그 알람을 타이머 알람과 똑같이 울린다
///   (같은 소리, ⌃⌥X로 끄기, 다시 울림, "다음 알람" 표시). 알린 기능은 자기 소리·알림을 내지 않는다.
/// - 한쪽에서 끄면 다른 쪽도 꺼진다: 울리는 쪽 → `ringerDid`, 알린 쪽 → `sourceDismissed`.
/// - 울리는 기능이 꺼져 있으면 알린 기능이 예전처럼 스스로 울린다.
@MainActor
public final class EppAlertBoard: ObservableObject {
    public static let shared = EppAlertBoard()

    public enum Event: Sendable {
        /// 울리는 쪽에서 껐다
        case dismissed
        /// 울리는 쪽에서 다시 울림을 눌렀다(그때 다시 publish해 주면 된다)
        case snoozed(until: Date)
    }

    @Published public private(set) var alerts: [EppAlert] = []
    /// 울리는 기능(타이머)이 켜져 있는지
    @Published public private(set) var hasRinger = false

    private var bySource: [String: [EppAlert]] = [:]
    private var handlers: [String: (String, Event) -> Void] = [:]
    private var ringerDismiss: ((String) -> Void)?

    // MARK: 알람이 있는 기능

    /// 이 기능의 다가오는 알람을 모두 바꾼다. 기능을 끌 때는 빈 목록.
    public func publish(_ alerts: [EppAlert], from source: String) {
        bySource[source] = alerts.isEmpty ? nil : alerts
        let merged = bySource.values.flatMap { $0 }.sorted { $0.date < $1.date }
        if merged != self.alerts { self.alerts = merged }
    }

    /// 울리는 쪽이 끄거나 다시 울림을 누르면 불린다(알람 id, 무엇을).
    public func onEvent(from source: String, _ handler: ((String, Event) -> Void)?) {
        handlers[source] = handler
    }

    /// 알린 쪽에서 직접 껐다(스티커에서 확인 등). 울리는 쪽도 멈춘다.
    public func sourceDismissed(_ alertID: String) {
        ringerDismiss?(alertID)
    }

    // MARK: 울리는 기능

    /// 울리는 기능이 켜질 때 등록하고, 꺼질 때 nil로 푼다. dismiss: 알린 쪽에서 끈 알람 id를 받는다.
    public func setRinger(dismiss: ((String) -> Void)?) {
        ringerDismiss = dismiss
        hasRinger = dismiss != nil
    }

    /// 울리는 쪽에서 끄거나 다시 울림을 눌렀을 때 알린 기능에 전한다.
    public func ringerDid(_ event: Event, alertID: String) {
        guard let alert = alerts.first(where: { $0.id == alertID }) else { return }
        handlers[alert.source]?(alertID, event)
    }

    public func isExternal(_ id: String) -> Bool { alerts.contains { $0.id == id } }
}
