import Foundation
import Testing
@testable import Clocky

private func makeDefaults() -> (UserDefaults, String) {
    let name = "ClockyMissed-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

@Suite(.serialized) struct MissedAndAwakeTests {
    @Test func 한_시간보다_늦은_알람은_울리지_않고_놓친_것으로_남긴다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        var notified = 0
        store.onMissed = { notified += 1 }
        let alarm = store.addAlarm(minutes: 7 * 60)
        store.renameAlarm(alarm, to: "기상")
        let late = Date().addingTimeInterval(-2 * 3600)
        store.forceNext(alarm, late)
        store.tick()
        #expect(!store.isRinging)
        #expect(store.missedAlerts.map(\.title) == ["기상"])
        #expect(abs((store.missedAlerts.first?.date ?? .distantPast).timeIntervalSince(late)) < 1)
        #expect(notified == 1)
        // 매일 알람은 다음 시각으로 넘어간다.
        #expect((store.alarms.first { $0.id == alarm }?.next ?? .distantPast) > Date())
        store.clearMissed()
        #expect(store.missedAlerts.isEmpty)
    }

    @Test func 늦지_않은_알람은_울리고_놓친_것이_아니다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let alarm = store.addAlarm(minutes: 7 * 60)
        store.forceNext(alarm, Date().addingTimeInterval(-60))
        store.tick()
        #expect(store.ringingAlarmIDs == [alarm])
        #expect(store.missedAlerts.isEmpty)
        store.stopRinging()
    }

    @Test func 꺼져_있는_동안_오래전에_끝난_타이머와_알람을_켤_때_알린다() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var timer = ClockStore.SavedTimer(id: UUID(), name: "빨래", duration: 600)
        timer.phase = "running"
        timer.endDate = Date().addingTimeInterval(-3 * 3600)
        defaults.set(try JSONEncoder().encode([timer]), forKey: "timers")
        let store = ClockStore(defaults: defaults)
        #expect(store.missedAlerts.map(\.title) == ["빨래"])
        #expect(store.timers[0].phase == .idle)
    }

    @Test func 타이머가_돌거나_10분_안에_울릴_것이_있으면_깨어_있게() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        #expect(!store.needsMacAwake)
        let alarm = store.addAlarm(minutes: 7 * 60)
        store.forceNext(alarm, Date().addingTimeInterval(30 * 60))
        store.tick()
        #expect(!store.needsMacAwake)
        store.forceNext(alarm, Date().addingTimeInterval(5 * 60))
        store.tick()
        #expect(store.needsMacAwake)
        store.keepsMacAwake = false
        #expect(!store.needsMacAwake)
        store.keepsMacAwake = true
        store.forceNext(alarm, Date().addingTimeInterval(30 * 60))
        store.tick()
        store.start(store.timers[0].id)
        #expect(store.needsMacAwake)
        store.pause(store.timers[0].id)
        #expect(!store.needsMacAwake)
    }

    @Test func 잠자기_막기를_켜고_끈다() {
        let guardian = SleepGuard()
        guardian.update(needsAwake: true)
        #expect(guardian.isHolding)
        guardian.update(needsAwake: false)
        #expect(!guardian.isHolding)
    }
}
