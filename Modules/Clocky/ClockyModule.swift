import AppKit
import Combine
import EppKit
import SwiftUI

/// 타이머(옛 Clocky): 넘김시계 타이머·알람·일정 알림. 원래 단독 앱(eddieee-git/mac-app-clocky)의 AppDelegate를 Epp 기능 약속에 맞게 옮긴 것.
///
/// 타이머가 돌거나 알람이 곧 울릴 때만 메뉴바에 남은 시간을 따로 띄운다(그게 타이머가 하는 일이라서).
/// 그 밖에는 Epp 아이콘 하나만 보이고, 메뉴는 Epp의 "타이머 ▸".
@MainActor
public final class ClockyModule: NSObject, EppModule, NSMenuDelegate {
    public static let info = EppModuleInfo(
        id: "clocky", storageName: "Clocky", nameKo: "타이머", nameEn: "Timer", symbol: "timer",
        summaryKo: "넘김시계 타이머·알람과 일정 알림",
        summaryEn: "Flip-clock timers, alarms and calendar alerts"
    )

    public static let permissionNeeds = [
        EppPermissionNeed(.calendar, required: false,
                          reasonKo: "Mac 캘린더 앱의 일정 시작 전에 울리기 (일정은 이 Mac 밖으로 보내지 않아요)",
                          reasonEn: "Ring before Mac Calendar events start (events never leave this Mac)"),
    ]

    private let context: EppContext
    let settings: ClockySettings
    private(set) lazy var window = TimerWindowController(settings: settings)
    private(set) lazy var calendarSync = CalendarSync(settings: settings, store: window.store)
    private(set) lazy var listWindow: ListWindowController = {
        listWindowLoaded = true
        let model = ClockListModel(store: window.store, settings: settings)
        model.onReveal = { [weak self] id in self?.reveal(id) }
        model.onOpenCalendarSettings = { [weak self] in self?.showCalendarSettings() }
        return ListWindowController(model: model, undoManager: window.sharedUndoManager)
    }()
    private var listWindowLoaded = false
    /// 남은 시간을 보여 줄 때만 만드는 메뉴바 항목.
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var showingAlarmIcon = false
    private var hotKeys: [HotKey] = []
    /// 곧 울릴 것이 있으면 Mac이 저절로 잠들지 않게 한다.
    private let sleepGuard = SleepGuard()

    private static let launchedKey = "hasLaunched"

    public required init(context: EppContext) {
        self.context = context
        // 여러 곳이 ClockyStorage를 쓰므로 Epp가 준 저장소로 먼저 바꿔 둔다.
        ClockyStorage.defaults = context.defaults
        ClockyStorage.folder = context.dataDirectory
        settings = ClockySettings(defaults: context.defaults)
        super.init()
    }

    public func start() {
        window.panel.onOpenSettings = { [weak self] in self?.context.openSettings() }
        window.panel.onOpenList = { [weak self] in self?.showList() }
        _ = calendarSync

        // 타이머가 도는 동안 메뉴바에 남은 시간을 띄운다.
        window.store.$now.combineLatest(window.store.$timers, window.store.$alarms, window.store.$calendarEvents)
            .sink { [weak self] _, _, _, _ in
                self?.updateStatusTitle()
                // 값이 바뀐 직후(willSet)에 불리므로 한 박자 뒤에 본다.
                DispatchQueue.main.async { self.map { $0.sleepGuard.update(needsAwake: $0.window.store.needsMacAwake) } }
            }
            .store(in: &subscriptions)
        // 단축키를 새로 누르는 동안에는 모두 풀어 둔다.
        settings.$hotKeys.combineLatest(settings.$isRecordingHotKey)
            .sink { [weak self] combos, isRecording in self?.registerHotKeys(isRecording ? [:] : combos) }
            .store(in: &subscriptions)
        // 설정에서 메뉴바 표시를 바꾸면 바로 고친다.
        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.updateStatusTitle() } }
            .store(in: &subscriptions)

        // 꺼져 있는 동안 놓친 것이 있으면 창에서 알린다.
        if !window.store.missedAlerts.isEmpty { window.show(takeFocus: false) }

        // 처음 켜면 무엇이 생겼는지 보이도록 시계 창을 띄운다.
        if !context.defaults.bool(forKey: Self.launchedKey) {
            context.defaults.set(true, forKey: Self.launchedKey)
            window.show()
        }
    }

    /// 저장하고 창·메뉴바 항목·단축키를 거둔다. 타이머와 캘린더 받기는 객체가 사라질 때 멈춘다(deinit).
    public func stop() {
        window.store.save()
        subscriptions.removeAll()
        hotKeys = []
        window.panel.orderOut(nil)
        if listWindowLoaded { listWindow.close() }
        removeStatusItem()
        context.setStatusText(nil)
        sleepGuard.update(needsAwake: false)
    }

    // MARK: 메뉴바의 남은 시간

    /// 여러 타이머가 돌면 가장 먼저 끝나는 것을 보여 준다. 도는 것이 없으면 일시정지한 것 중에서 고른다.
    /// 보여 줄 것이 없으면 메뉴바 항목을 없앤다(Epp 아이콘 하나만 남게).
    private func updateStatusTitle() {
        let store = window.store
        let now = store.now
        let active = store.timers.filter { $0.phase == .ringing }.first
            ?? store.timers.filter { $0.phase == .running }.min { $0.remaining(at: now) < $1.remaining(at: now) }
        let paused = store.timers.filter { $0.phase == .paused }.min { $0.remaining(at: now) < $1.remaining(at: now) }
        var title = ""
        // 도는 타이머가 없으면 1시간 안에 울릴 알람까지 남은 시간을 알람 시계 모양과 함께 보여 준다.
        // 그것도 없으면 일시정지한 타이머를 보여 준다.
        var showsAlarm = false
        if let active, settings.menuBarShowsTimer {
            title = " " + clockText(active.remaining(at: now))
        } else if active == nil || !settings.menuBarShowsTimer, settings.menuBarShowsAlarm,
                  let soonest = store.nextAlert?.date,
                  case let left = soonest.timeIntervalSince(now), left > 0 && left <= ClockStore.menuBarAlarmWindow {
            title = " " + clockText(Int(ceil(left - 0.001)))
            showsAlarm = true
        } else if let paused, settings.menuBarShowsTimer {
            title = " " + clockText(paused.remaining(at: now))
        }
        guard !title.isEmpty else {
            context.setStatusText(nil)
            return removeStatusItem()
        }
        guard settings.menuBarSeparateItem else {
            // Epp 아이콘 옆에 붙인다. 알람이면 알람 시계 글자를 앞에 둔다.
            removeStatusItem()
            context.setStatusText((showsAlarm ? "⏰" : "") + title.trimmingCharacters(in: .whitespaces))
            return
        }
        context.setStatusText(nil)
        let item = statusItem ?? makeStatusItem()
        if showsAlarm != showingAlarmIcon || item.button?.image == nil {
            showingAlarmIcon = showsAlarm
            item.button?.image = showsAlarm ? MenuBarIcon.alarm() : MenuBarIcon.make()
        }
        guard let button = item.button, button.title != title else { return }
        button.title = title
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "ClockyRemaining"
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        return item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        showingAlarmIcon = false
    }

    /// 남은 시간 항목을 누르면 Epp 메뉴의 "타이머 ▸"와 같은 메뉴를 보여 준다.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fillMenu(menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("타이머 설정…"), action: #selector(openSettingsFromMenu), keyEquivalent: "").target = self
    }

    @objc private func openSettingsFromMenu() { context.openSettings() }

    // MARK: Epp 메뉴의 "타이머 ▸"

    /// 시계 창 열기, 도는·멈춘 타이머와 켜 둔 알람(누르면 그 항목을 창에 띄움), 전체 목록.
    public func fillMenu(_ menu: NSMenu) {
        menu.addItem(withTitle: L("시계 창 열기"), action: #selector(showWindow), keyEquivalent: "").target = self
        let lines = statusLines()
        if !lines.isEmpty { menu.addItem(.separator()) }
        for line in lines {
            let item = menu.addItem(withTitle: line.0, action: #selector(showItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = line.1
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("전체 목록…"), action: #selector(showList), keyEquivalent: "").target = self
    }

    private func statusLines() -> [(String, String)] {
        let store = window.store
        let now = Date()
        var lines: [(String, String)] = []
        for missed in store.missedAlerts.suffix(3) {
            lines.append((L("⚠︎ 놓친 알림: %@ · %@", missed.title, settings.dayText(missed.date) + " " + settings.timeText(missed.date)), "missed:"))
        }
        // 곧(1시간 안) 울릴 것이 있는데 Mac 소리가 꺼져 있으면 알린다.
        let soon = store.timers.contains { $0.phase == .running } || (store.nextAlert.map { $0.date.timeIntervalSince(now) < 3600 } ?? false)
        if soon && SystemVolume.isSilent {
            lines.append((L("🔇 Mac 소리가 꺼져 있어 알람이 들리지 않아요"), "volume:"))
        }
        for item in store.timers {
            let name = store.displayName(of: item)
            switch item.phase {
            case .running: lines.append((L("%@ · %@ 남음", name, clockText(item.remaining(at: now))), "timer:\(item.id)"))
            case .paused: lines.append((L("%@ · 일시정지 %@", name, clockText(item.remaining(at: now))), "timer:\(item.id)"))
            case .idle, .ringing: break
            }
        }
        for item in store.upcomingAlarms {
            guard let next = item.upcoming else { continue }
            lines.append((L("%@ · %@ (%@ 남음)", store.displayName(of: item), settings.timeText(next),
                            remainingText(until: next, from: now)), "alarm:\(item.id)"))
        }
        // 하루 안의 일정은 다섯 개까지.
        for (event, alert) in store.pendingEventAlerts.filter({ $0.date > now && $0.date < now.addingTimeInterval(86400) }).prefix(5) {
            lines.append((L("📅 %@ · %@ 시작 (알림까지 %@)", event.title, settings.timeText(event.start),
                            remainingText(until: alert, from: now)), "event:\(event.listID)"))
        }
        return lines
    }

    /// 앱 메뉴 "윈도우"에 전체 목록(⌘L). 시계 창·목록 창에서 쓰던 키.
    public func mainMenus() -> [EppMainMenu] {
        let window = NSMenu(title: L("윈도우"))
        window.addItem(withTitle: L("전체 목록…"), action: #selector(showList), keyEquivalent: "l").target = self
        return [EppMainMenu(.window, window)]
    }

    // MARK: 단축키

    private func registerHotKeys(_ combos: [String: KeyCombo]) {
        hotKeys = []
        var failed = Set<HotKeyAction>()
        for action in HotKeyAction.allCases {
            guard let combo = combos[action.rawValue] else { continue }
            if let hotKey = HotKey(combo: combo, action: { [weak self] in self?.perform(action) }) {
                hotKeys.append(hotKey)
            } else {
                failed.insert(action)
            }
        }
        if settings.failedHotKeys != failed { settings.failedHotKeys = failed }
    }

    func perform(_ action: HotKeyAction) {
        let store = window.store
        switch action {
        case .toggleClock:
            if window.isVisible && window.panel.isKeyWindow { window.panel.close() } else { window.show() }
        case .toggleTimer:
            store.toggle(store.selectedTimerID)
        case .stopRinging:
            store.stopRinging()
        case .showList:
            showList()
        }
    }

    public func globalShortcuts() -> [EppShortcutInfo] {
        HotKeyAction.allCases.compactMap { action in
            settings.hotKeys[action.rawValue].map { EppShortcutInfo(title: action.title, keys: $0.displayText) }
        }
    }

    // MARK: 동작

    @objc private func showWindow() { window.show() }

    /// 설정의 캘린더 탭을 바로 연다.
    func showCalendarSettings() {
        UserDefaults.standard.set("calendar", forKey: EppSettingsKeys.tab(Self.info.id))
        context.openSettings()
    }

    @objc func showList() { listWindow.show() }

    /// 목록에서 고른 항목을 시계 창에 띄운다.
    func reveal(_ id: UUID) {
        let store = window.store
        if store.timers.contains(where: { $0.id == id }) {
            store.selectedTimerID = id
            store.mode = .timer
        } else if store.alarms.contains(where: { $0.id == id }) {
            store.selectedAlarmID = id
            store.mode = .alarm
        }
        window.show()
    }

    @objc private func showItem(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, key == "missed:" || key == "volume:" {
            return window.show()
        }
        guard let key = sender.representedObject as? String,
              let id = key.split(separator: ":").last.flatMap({ UUID(uuidString: String($0)) }) else { return window.show() }
        // 일정은 목록 창에서 자세히 본다.
        if key.hasPrefix("event:") {
            showList()
            listWindow.model.filter = .calendar
            listWindow.model.selection = [id]
            return
        }
        reveal(id)
    }

    /// epp://clocky/show — 시계 창, epp://clocky/list — 전체 목록, epp://clocky/toggle — 고른 타이머 시작/일시정지
    /// 빠른 검색: 타이머·알람 이름에서 찾는다. 고르면 시계 창에서 그 항목을 고른다.
    public func search(_ query: EppSearchQuery) -> [EppSearchResult] {
        let store = window.store
        let timers = store.timers.filter { query.matches(store.displayName(of: $0)) }.map { timer in
            EppSearchResult(id: "clocky.t." + timer.id.uuidString, title: store.displayName(of: timer),
                            detail: L("타이머") + " · " + clockText(timer.duration), symbol: "timer") { [weak self] in
                self?.window.store.selectedTimerID = timer.id
                self?.window.show()
            }
        }
        let alarms = store.alarms.filter { query.matches(store.displayName(of: $0)) }.map { alarm in
            EppSearchResult(id: "clocky.a." + alarm.id.uuidString, title: store.displayName(of: alarm),
                            detail: L("알람") + " · " + String(format: "%02d:%02d", alarm.minutes / 60, alarm.minutes % 60),
                            symbol: "alarm") { [weak self] in
                self?.window.store.selectedAlarmID = alarm.id
                self?.window.show()
            }
        }
        return timers + alarms
    }

    public func handle(url: URL) {
        switch url.pathComponents.dropFirst().first ?? "show" {
        case "list": showList()
        case "toggle": perform(.toggleTimer)
        case "show": window.show()
        default: EppLog.write("타이머", "모르는 주소 명령 무시: \(url.path)")
        }
    }

    // MARK: Epp 설정

    public func settingsTabs() -> [EppSettingsTab] {
        ClockySettingsTabs.tabs(settings: settings, calendar: calendarSync)
    }

    public func makeGettingStarted() -> AnyView? {
        AnyView(ClockyGettingStarted(store: window.store, settings: settings,
                                     openClock: { [weak self] in self?.window.show() }))
    }

    /// 단위 시험은 `swift test`(Tests/ClockyTests)로 돈다. 여기서는 기본값만 본다.
    public static func runSelfTest() -> Bool {
        var ok = true
        func expect(_ condition: Bool, _ name: String) {
            print(condition ? "  ✓ \(name)" : "  ✗ \(name)")
            ok = ok && condition
        }
        expect(KeyCombo.defaults[HotKeyAction.toggleClock.rawValue]?.displayText == "⌃⌥C", "시계 창 기본 ⌃⌥C")
        let suite = "clocky-selftest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ClockySettings(defaults: defaults)
        expect(settings.hotKeys == KeyCombo.defaults && settings.snoozeMinutes == 5, "기본값")
        expect(Localization.english["울림 끄기"] != nil, "영어 사전 읽기")
        return ok
    }
}

/// 설정 맨 위 시작하기 상자. 끝낸 단계는 체크로 바뀐다.
struct ClockyGettingStarted: View {
    @ObservedObject var store: ClockStore
    @ObservedObject var settings: ClockySettings
    let openClock: () -> Void

    var body: some View {
        let clockKeys = settings.hotKeys[HotKeyAction.toggleClock.rawValue]?.displayText ?? L("메뉴")
        EppStepList([
            .init(L("%@로 시계 창을 열고 타이머 시작하기", clockKeys),
                  done: store.timers.contains { $0.phase != .idle },
                  action: (L("시계 창 열기"), openClock)),
            .init(L("시계 창에서 알람 켜기"), done: store.alarms.contains { $0.enabled }),
            .init(L("(선택) 캘린더 탭에서 일정 연결하기"),
                  done: !settings.calendarFeeds.isEmpty || settings.macCalendarEnabled),
        ], footer: L("타이머가 돌거나 알람이 1시간 안에 울리면 메뉴바에 남은 시간이 따로 보여요."))
    }
}
