import Foundation
import Testing
@testable import Clocky

/// 다른 기능(스티커)의 알람을 타이머가 타이머 알람과 똑같이 울리는지(EppAlertBoard → ClockStore).
@Suite(.serialized) struct ExternalAlertTests {
    private func makeStore() -> (ClockStore, UserDefaults, String) {
        let name = "ClockyExternalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ClockStore(defaults: defaults), defaults, name)
    }

    private func sticky(_ title: String, at seconds: TimeInterval) -> CalendarEvent {
        let date = Date().addingTimeInterval(seconds)
        return CalendarEvent(id: "floaty|\(UUID().uuidString)|\(Int(date.timeIntervalSince1970))", title: title,
                             start: date, end: date.addingTimeInterval(60), calendarName: "스티커", feedID: ClockStore.externalFeedID)
    }

    @Test func 미리_알림_없이_그_시각에_울리고_끄면_스티커에_알린다() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.calendarLead = 600
        let soon = sticky("📝 장보기", at: 300)
        store.setExternalEvents([soon])
        store.tick()
        #expect(!store.isRinging, "캘린더 미리 알림 시간(10분)을 쓰지 않는다")
        let due = sticky("📝 약 먹기", at: -1)
        store.setExternalEvents([soon, due])
        store.tick()
        #expect(store.ringingEventIDs == [due.id] && store.mode == .alarm)
        var stopped: ([String], Date?)?
        store.onExternalStopped = { stopped = ($0, $1) }
        store.stopRinging()
        #expect(stopped?.0 == [due.id] && stopped?.1 == nil)
    }

    @Test func 다시_울림은_스티커가_새_시각으로_올린다() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.snoozeMinutes = 5
        let due = sticky("📝 회의", at: -1)
        store.setExternalEvents([due])
        store.tick()
        var until: Date?
        store.onExternalStopped = { _, date in until = date }
        store.snooze()
        #expect(until.map { abs($0.timeIntervalSinceNow - 300) < 2 } == true)
        #expect(store.eventSnoozes[due.id] == nil, "타이머가 따로 다시 걸지 않는다(두 번 울리지 않게)")
        store.tick()
        #expect(!store.isRinging)
    }

    @Test func 스티커에서_끄면_그_알람만_멈춘다() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let due = sticky("📝 물 주기", at: -1)
        store.setExternalEvents([due])
        store.tick()
        #expect(store.isRinging)
        store.dismissExternal(due.id)
        #expect(!store.isRinging)
        store.tick()
        #expect(!store.isRinging && store.pendingEventAlerts.isEmpty)
    }
}

@Suite(.serialized) struct AlarmNoteTests {
    @Test func 알람_메모를_저장하고_복제하고_울릴_때_보여_준다() {
        let name = "ClockyNoteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let id = store.addAlarm()
        store.setAlarmNote(id, "  약 먹고 물 마시기 \n")
        store.save()
        let again = ClockStore(defaults: defaults)
        #expect(again.alarms.first { $0.id == id }?.note == "  약 먹고 물 마시기 \n")
        #expect(again.ringingNotes.isEmpty, "울리지 않으면 메모도 안 보인다")
        let copy = again.duplicateAlarm(id)
        #expect(again.alarms.first { $0.id == copy }?.note == "  약 먹고 물 마시기 \n", "복제해도 메모가 따라간다")
    }
}
