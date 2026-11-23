import AppKit
import EppKit
import UniformTypeIdentifiers

/// 메뉴에서 바꾸는 설정. 창 화면은 이것을 지켜보다 다시 그린다.
final class ClockySettings: ObservableObject {
    private enum Keys {
        static let language = "language", alarmSound = "alarmSound", volume = "soundVolume"
        static let warning = "warningSeconds", snooze = "snoozeMinutes", soundLimit = "soundLimitSeconds"
        static let keepMacAwake = "keepMacAwake"
        static let menuBarTimer = "menuBarShowsTimer", menuBarAlarm = "menuBarShowsAlarm", confirmDelete = "confirmDelete"
        static let presets = "timerPresets", hotKeys = "hotKeys"
        static let calendarFeeds = "calendarFeeds", calendarLead = "calendarLeadMinutes"
        static let calendarAllDay = "calendarIncludeAllDay", calendarDeclined = "calendarIncludeDeclined"
        static let macCalendar = "macCalendarEnabled", macCalendarIDs = "macCalendarIDs"
    }
    static let warningChoices = [0, 5, 10, 30, 60]
    static let snoozeChoices = [1, 3, 5, 10, 15, 30]
    static let soundLimitChoices = [10, 30, 60, 180, 300]
    static let defaultPresets = [1, 3, 5, 10, 25]
    static let calendarLeadChoices = [0, 1, 5, 10, 15, 30]
    /// 시계 창 한 줄에 들어가는 만큼.
    static let maxPresets = 6
    private let defaults: UserDefaults

    /// 화면 언어. Epp 설정 → 일반 → 언어를 따른다(바꾸면 Epp를 다시 연다).
    /// 화면을 언어에 맞춰 다시 그리는 표시(.id)
    var language: String { EppLanguage.isKorean ? "ko" : "en" }
    /// 시스템 사운드 이름.
    @Published var alarmSound: String {
        didSet {
            defaults.set(alarmSound, forKey: Keys.alarmSound)
            AlarmSound.name = alarmSound
        }
    }
    /// 알람 소리 크기. 0~1.
    @Published var soundVolume: Double {
        didSet {
            defaults.set(soundVolume, forKey: Keys.volume)
            AlarmSound.volume = Float(soundVolume)
        }
    }
    /// 끝나기 몇 초 전부터 창을 깜빡일지. 0이면 깜빡이지 않는다.
    @Published var warningSeconds: Int { didSet { defaults.set(warningSeconds, forKey: Keys.warning) } }
    @Published var snoozeMinutes: Int { didSet { defaults.set(snoozeMinutes, forKey: Keys.snooze) } }
    /// 끄지 않으면 소리를 몇 초까지 되풀이할지. 깜빡임은 끌 때까지 계속된다.
    @Published var soundLimitSeconds: Int { didSet { defaults.set(soundLimitSeconds, forKey: Keys.soundLimit) } }
    /// 타이머가 돌거나 10분 안에 울릴 것이 있으면 Mac이 저절로 잠들지 않게 한다. 기본 켬.
    @Published var keepMacAwake: Bool { didSet { defaults.set(keepMacAwake, forKey: Keys.keepMacAwake) } }
    @Published var menuBarShowsTimer: Bool { didSet { defaults.set(menuBarShowsTimer, forKey: Keys.menuBarTimer) } }
    @Published var menuBarShowsAlarm: Bool { didSet { defaults.set(menuBarShowsAlarm, forKey: Keys.menuBarAlarm) } }
    /// 지우기 전에 묻는다. 꺼 두어도 ⌘Z로 되살릴 수 있다.
    @Published var confirmDelete: Bool { didSet { defaults.set(confirmDelete, forKey: Keys.confirmDelete) } }
    /// 타이머 시간 버튼(분). 1~6개.
    @Published var timerPresets: [Int] { didSet { defaults.set(timerPresets, forKey: Keys.presets) } }
    /// 전역 단축키. 동작 이름 → 키 조합. 없는 동작은 단축키가 없다.
    @Published var hotKeys: [String: KeyCombo] {
        didSet { defaults.set(try? JSONEncoder().encode(hotKeys), forKey: Keys.hotKeys) }
    }
    /// 구글 캘린더 등의 iCal 주소. 비밀 토큰이 들어 있어 화면에는 가려서 보여 준다.
    @Published var calendarFeeds: [CalendarFeed] {
        didSet { defaults.set(try? JSONEncoder().encode(calendarFeeds), forKey: Keys.calendarFeeds) }
    }
    /// 일정 시작 몇 분 전에 울릴지. 0이면 시작할 때.
    @Published var calendarLeadMinutes: Int { didSet { defaults.set(calendarLeadMinutes, forKey: Keys.calendarLead) } }
    @Published var calendarIncludeAllDay: Bool { didSet { defaults.set(calendarIncludeAllDay, forKey: Keys.calendarAllDay) } }
    @Published var calendarIncludeDeclined: Bool { didSet { defaults.set(calendarIncludeDeclined, forKey: Keys.calendarDeclined) } }
    /// Mac 캘린더 앱의 일정으로도 알릴지.
    @Published var macCalendarEnabled: Bool { didSet { defaults.set(macCalendarEnabled, forKey: Keys.macCalendar) } }
    /// 알림을 받을 Mac 캘린더. nil이면 모든 캘린더.
    @Published var macCalendarIDs: [String]? {
        didSet {
            if let macCalendarIDs { defaults.set(macCalendarIDs, forKey: Keys.macCalendarIDs) } else { defaults.removeObject(forKey: Keys.macCalendarIDs) }
        }
    }
    /// 하루에 한 번 GitHub에 새 버전이 있는지 묻는다.
    /// 다른 앱이 이미 쓰는 등의 이유로 등록하지 못한 단축키.
    @Published var failedHotKeys: Set<HotKeyAction> = []
    /// 단축키를 새로 누르는 동안에는 등록을 풀어 둔다. 그래야 지금 단축키도 다시 고를 수 있다.
    @Published var isRecordingHotKey = false
    /// defaults: Epp가 준 타이머 기능 전용 저장소(점검에서는 임시 저장소).
    init(defaults: UserDefaults = ClockyStorage.defaults) {
        self.defaults = defaults
        alarmSound = defaults.string(forKey: Keys.alarmSound).flatMap { AlarmSound.isAvailable($0) ? $0 : nil }
            ?? AlarmSound.defaultName
        soundVolume = min(max(defaults.object(forKey: Keys.volume) as? Double ?? 1, 0), 1)
        warningSeconds = (defaults.object(forKey: Keys.warning) as? Int).flatMap { Self.warningChoices.contains($0) ? $0 : nil } ?? 10
        snoozeMinutes = (defaults.object(forKey: Keys.snooze) as? Int).flatMap { Self.snoozeChoices.contains($0) ? $0 : nil } ?? 5
        keepMacAwake = defaults.object(forKey: Keys.keepMacAwake) as? Bool ?? true
        soundLimitSeconds = (defaults.object(forKey: Keys.soundLimit) as? Int)
            .flatMap { Self.soundLimitChoices.contains($0) ? $0 : nil } ?? 60
        menuBarShowsTimer = defaults.object(forKey: Keys.menuBarTimer) as? Bool ?? true
        menuBarShowsAlarm = defaults.object(forKey: Keys.menuBarAlarm) as? Bool ?? true
        confirmDelete = defaults.bool(forKey: Keys.confirmDelete)
        timerPresets = (defaults.array(forKey: Keys.presets) as? [Int]).flatMap { Self.validPresets($0) } ?? Self.defaultPresets
        calendarFeeds = defaults.data(forKey: Keys.calendarFeeds)
            .flatMap { try? JSONDecoder().decode([CalendarFeed].self, from: $0) } ?? []
        calendarLeadMinutes = (defaults.object(forKey: Keys.calendarLead) as? Int)
            .flatMap { Self.calendarLeadChoices.contains($0) ? $0 : nil } ?? 5
        calendarIncludeAllDay = defaults.bool(forKey: Keys.calendarAllDay)
        calendarIncludeDeclined = defaults.bool(forKey: Keys.calendarDeclined)
        macCalendarEnabled = defaults.bool(forKey: Keys.macCalendar)
        macCalendarIDs = defaults.stringArray(forKey: Keys.macCalendarIDs)
        hotKeys = defaults.data(forKey: Keys.hotKeys).flatMap { try? JSONDecoder().decode([String: KeyCombo].self, from: $0) }
            ?? KeyCombo.defaults
        AlarmSound.name = alarmSound
        AlarmSound.volume = Float(soundVolume)
    }

    /// 1분~99시간 사이, 겹치지 않게, 작은 것부터, 많아야 6개. 남는 것이 없으면 nil.
    static func validPresets(_ minutes: [Int]) -> [Int]? {
        let valid = Array(Set(minutes.filter { (1...5999).contains($0) })).sorted().prefix(maxPresets)
        return valid.isEmpty ? nil : Array(valid)
    }

    /// "1, 3, 5" 같은 글을 버튼 목록으로 바꾼다.
    static func parsePresets(_ text: String) -> [Int]? {
        validPresets(text.split(whereSeparator: { ",; ".contains($0) }).compactMap { Int($0) })
    }

    /// 지우기 전에 확인을 켜 두었으면 묻는다. 지워도 되면 true.
    func confirmRemoval(count: Int) -> Bool {
        guard confirmDelete else { return true }
        let alert = NSAlert()
        alert.messageText = count == 1 ? L("지울까요?") : L("%d개를 지울까요?", count)
        alert.informativeText = L("지운 뒤에도 ⌘Z로 되살릴 수 있어요.")
        alert.addButton(withTitle: L("삭제"))
        alert.addButton(withTitle: L("취소"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }


    /// 시각 고르기 칸도 앱 언어를 따르게 한다. 그러지 않으면 한국어 화면에 "7:30 AM"이 나온다.
    var locale: Locale { Locale(identifier: EppLanguage.isKorean ? "ko_KR" : "en_US") }

    /// "오전 9:00" 또는 "9:00 AM".
    func timeText(_ date: Date) -> String {
        formatter(EppLanguage.isKorean ? "a h:mm" : "h:mm a").string(from: date)
    }

    /// "오늘", "내일", "어제", 그 밖에는 "수요일"·"Wednesday".
    func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("오늘") }
        if calendar.isDateInTomorrow(date) { return L("내일") }
        if calendar.isDateInYesterday(date) { return L("어제") }
        return formatter("EEEE").string(from: date)
    }

    /// 목록을 그릴 때마다 만들지 않도록 언어·형식마다 하나씩 둔다. 시간대가 바뀌면 다시 만든다.
    private var formatters: [String: DateFormatter] = [:]

    private func formatter(_ format: String) -> DateFormatter {
        let key = "\(language)|\(format)|\(TimeZone.current.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: EppLanguage.isKorean ? "ko_KR" : "en_US")
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
}

/// 타이머와 알람이 끝났을 때 내는 소리.
/// 타이머와 알람이 끝났을 때 내는 소리. 시스템 사운드 이름이나 "file:파일 이름"으로 가리킨다.
/// 내 소리 파일은 앱 지원 폴더의 Sounds에 복사해 두고 쓴다.
enum AlarmSound {
    static let defaultName = "Glass"
    static let systemChoices = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                                "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    static let filePrefix = "file:"
    /// 설정에서 고른 기본 소리.
    static var name = defaultName
    static var volume: Float = 1
    /// 앞 소리가 끝나기 전에 다시 내려면 같은 객체를 멈췄다 다시 틀어야 한다.
    private static var current: NSSound?

    static var folder: URL { ClockyStorage.folder.appendingPathComponent("Sounds", isDirectory: true) }

    /// 복사해 둔 내 소리 파일들. 이름 순.
    static var customChoices: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.filter { !$0.hasPrefix(".") }.sorted().map { filePrefix + $0 }
    }

    static var choices: [String] { systemChoices + customChoices }

    static func isAvailable(_ id: String) -> Bool {
        systemChoices.contains(id) || customChoices.contains(id)
    }

    /// 메뉴에 보일 이름. 내 파일은 확장자를 뗀다.
    static func title(_ id: String) -> String {
        guard id.hasPrefix(filePrefix) else { return id }
        return (String(id.dropFirst(filePrefix.count)) as NSString).deletingPathExtension
    }

    /// 고른 파일을 Sounds 폴더로 복사하고 그 소리의 이름을 돌려준다. 소리로 열 수 없는 파일이면 nil.
    static func importFile(_ url: URL) -> String? {
        guard NSSound(contentsOf: url, byReference: true) != nil else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(url.lastPathComponent)
        var index = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let base = url.deletingPathExtension().lastPathComponent
            target = folder.appendingPathComponent("\(base) \(index).\(url.pathExtension)")
            index += 1
        }
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return nil }
        return filePrefix + target.lastPathComponent
    }

    static func removeFile(_ id: String) {
        guard id.hasPrefix(filePrefix) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(String(id.dropFirst(filePrefix.count))))
    }

    private static func sound(_ id: String) -> NSSound? {
        if id.hasPrefix(filePrefix) {
            let url = folder.appendingPathComponent(String(id.dropFirst(filePrefix.count)))
            return NSSound(contentsOf: url, byReference: false)
        }
        return NSSound(named: id)
    }

    /// 주어진 소리를 낸다. 없거나 지워진 소리면 기본 소리, 그것도 없으면 Glass를 낸다.
    static func play(_ id: String? = nil) {
        current?.stop()
        current = sound(id ?? name) ?? sound(name) ?? NSSound(named: defaultName)
        current?.volume = volume
        current?.play()
    }

    static func stop() {
        current?.stop()
        current = nil
    }
}

enum Localization {
    static let translations = EppTranslations(pairs)
    static var english: [String: String] { translations.english }
    /// 자체 점검용: 두 번 들어간 키.
    static var duplicateKeys: [String] { translations.duplicateKeys }

    static let pairs: [(String, String)] = [
        // Epp
        ("%@로 시계 창을 열고 타이머 시작하기", "Open the clock with %@ and start a timer"),
        ("(선택) 캘린더 탭에서 일정 연결하기", "(Optional) Connect your calendar in the Calendar tab"),
        ("메뉴", "the menu"),
        ("시계 창 열기", "Open Clock"),
        ("시계 창에서 알람 켜기", "Turn on an alarm in the clock window"),
        ("윈도우", "Window"),
        ("전역 단축키", "Global shortcuts"),
        ("타이머 설정…", "Timer Settings…"),
        ("타이머가 돌거나 알람이 1시간 안에 울리면 메뉴바에 남은 시간이 따로 보여요.", "While a timer runs or an alarm is due within an hour, the time left shows in the menu bar."),
        // 메뉴
        ("%@ · 일시정지 %@", "%@ · paused %@"),
        ("%@ · %@ (%@ 남음)", "%@ · %@ (in %@)"),
        ("알람 소리", "Alarm Sound"),
        // 창
        ("이름", "Name"),
        ("타이머", "Timer"),
        ("알람", "Alarm"),
        ("항상 위", "Always on Top"),
        ("항상 위 해제", "Turn Off Always on Top"),
        ("직접…", "Custom…"),
        ("시작", "Start"),
        ("일시정지", "Pause"),
        ("계속", "Resume"),
        ("초기화", "Reset"),
        ("알람 추가를 눌러 시각을 등록해요", "Click Add Alarm to set a time"),
        // 목록
        ("타이머 %d", "Timer %d"),
        ("창을 누르거나 Esc로 끄기", "Click the window or press Esc to stop"),
        ("%d분 뒤 다시 울림", "Snooze %d min"),
        ("S 키로도 돼요", "You can also press S"),
        ("다시 울림", "Snoozed"),
        ("반복", "Repeat"),
        ("평일", "Weekdays"),
        ("주말", "Weekends"),
        ("일", "Sun"),
        ("월", "Mon"),
        ("화", "Tue"),
        ("수", "Wed"),
        ("목", "Thu"),
        ("금", "Fri"),
        ("토", "Sat"),
        ("켜짐", "On"),
        ("꺼짐", "Off"),
        ("%@ 시작", "Start %@"),
        ("%@ 일시정지", "Pause %@"),
        ("%@ 삭제", "Delete %@"),
        ("%@ 켜기", "%@ on"),
        ("고르기", "Select"),
        ("알람 %d", "Alarm %d"),
        ("타이머 %d개", "Timers: %d"),
        ("알람 %d개", "Alarms: %d"),
        ("타이머 추가", "Add Timer"),
        ("알람 추가", "Add Alarm"),
        ("등록된 알람이 없어요", "No alarms yet"),
        ("삭제", "Delete"),
        ("삭제 (⌘Z로 되돌리기)", "Delete (⌘Z to undo)"),
        ("타이머 삭제", "Delete Timer"),
        ("알람 삭제", "Delete Alarm"),
        ("대기", "Ready"),
        ("진행 중", "Running"),
        ("일시정지됨", "Paused"),
        ("울림", "Ringing"),
        ("한 번", "Once"),
        ("%@ · %@ 남음", "%@ · %@ left"),
        ("%@ · 꺼짐", "%@ · off"),
        ("매일", "Daily"),
        ("켜기", "On"),
        ("알람 꺼짐", "Alarm off"),
        ("오늘", "today"),
        ("내일", "tomorrow"),
        ("%@ %@에 울림 · %@ 남음", "Rings %@ at %@ · in %@"),
        ("시간 입력", "Set Time"),
        ("분, 분:초, 또는 시:분:초로 입력해요. 예: 90, 5:30, 1:30:00", "Enter minutes, m:ss, or h:mm:ss. For example: 90, 5:30, 1:30:00"),
        ("설정", "Set"),
        ("취소", "Cancel"),
        // 남은 시간
        ("%d일 %d시간", "%dd %dh"),
        ("%d일", "%dd"),
        ("%d시간 %d분", "%dh %dm"),
        ("%d시간", "%dh"),
        ("%d분", "%dm"),
        ("%d초", "%ds"),
        // 설정 창
        ("일반", "General"),
        ("타이머·알람", "Timers & Alarms"),
        ("소리", "Sound"),
        ("단축키", "Shortcuts"),
        ("삭제하기 전에 확인", "Confirm before deleting"),
        ("메뉴바", "Menu Bar"),
        ("타이머 남은 시간 표시", "Show timer countdown"),
        ("1시간 안에 울릴 알람까지 남은 시간 표시", "Show countdown to alarms within an hour"),
        ("미리 깜빡이기", "Flash before ringing"),
        ("깜빡이지 않음", "Don't flash"),
        ("%d초 전부터", "%d seconds before"),
        ("다시 울림 간격", "Snooze length"),
        ("소리를 되풀이하는 시간", "Keep ringing for"),
        ("소리가 멈춘 뒤에도 끌 때까지 창은 깜빡여요.", "The window keeps flashing until you stop it, even after the sound ends."),
        ("소리 크기", "Volume"),
        ("들어 보기", "Preview"),
        ("Mac의 소리를 꺼 두면 알람도 들리지 않아요.", "If your Mac is muted, alarms are silent too."),
        ("시계 창", "Clock Window"),
        ("스페이스", "Space"),
        ("고른 타이머 시작·일시정지, 고른 알람 켜기·끄기", "Start or pause the timer, turn the alarm on or off"),
        ("목록에서 고르기", "Select in the list"),
        ("타이머 또는 알람 추가", "Add a timer or alarm"),
        ("고른 항목 지우기", "Delete the selected item"),
        ("지운 항목 되살리기, 다시 지우기", "Undo or redo a delete"),
        ("타이머, 알람", "Timers, alarms"),
        ("울림 끄기, 이름 편집 끝내기", "Stop ringing, finish editing a name"),
        ("울리는 동안 다시 울림", "Snooze while ringing"),
        ("지울까요?", "Delete this item?"),
        ("%d개를 지울까요?", "Delete %d items?"),
        ("지운 뒤에도 ⌘Z로 되살릴 수 있어요.", "You can bring it back with ⌘Z."),
        // 전체 목록
        ("전체 목록", "All Timers & Alarms"),
        ("전체 목록…", "All Timers & Alarms…"),
        ("전체", "All"),
        ("보기", "Show"),
        ("이름 검색", "Search names"),
        ("알람 정렬", "Sort alarms"),
        ("다음 울림 순", "Next to ring"),
        ("시각 순", "Time"),
        ("이름 순", "Name"),
        ("추가한 순", "Date added"),
        ("추가", "Add"),
        ("새 타이머", "New Timer"),
        ("새 알람", "New Alarm"),
        ("찾는 항목이 없어요", "No matches"),
        ("왼쪽에서 타이머나 알람을 고르세요", "Select a timer or alarm on the left"),
        ("시계 창에서 보기", "Show in Clock Window"),
        ("복제", "Duplicate"),
        ("끄기", "Off"),
        ("남은 시간", "Time left"),
        ("상태", "Status"),
        ("시간", "Duration"),
        ("시각", "Time"),
        ("다음 울림", "Next"),
        ("요일 지정", "Custom"),
        ("%@ %@ · %@ 남음", "%@ %@ · in %@"),
        ("분, 분:초, 또는 시:분:초로 입력하고 Return을 눌러요. 시간을 바꾸면 처음부터 다시 세요.", "Enter minutes, m:ss, or h:mm:ss and press Return. Changing the duration starts the count over."),
        ("%d개 선택됨", "%d selected"),
        ("알람 모두 켜기", "Turn All Alarms On"),
        ("알람 모두 끄기", "Turn All Alarms Off"),
        ("울리는 중: %@", "Ringing: %@"),
        ("전체 목록 (⌘L)", "All Timers & Alarms (⌘L)"),
        ("설정 (⌘,)", "Settings (⌘,)"),
        ("%@, %@ 남음", "%@, %@ left"),
        ("지금 시각 %@", "Current time %@"),
        ("설정 열기", "Open Settings"),
        ("기본 (%@)", "Default (%@)"),
        ("이 파일 지우기", "Remove This File"),
        ("내 소리 파일 추가…", "Add Sound File…"),
        ("알람으로 쓸 소리 파일을 고르세요. Epp 폴더로 복사해 둬요.", "Choose a sound file for alarms. Epp keeps a copy."),
        ("이 파일은 소리로 열 수 없어요.", "This file can't be opened as a sound."),
        ("시계 창과 목록 창의 시간 버튼이에요. 분 단위로 쉼표를 넣어 적고 Return을 눌러요. 6개까지 써요.", "Duration buttons in the clock and list windows. Enter minutes separated by commas and press Return. Up to 6."),
        ("타이머 버튼(분)", "Timer buttons (min)"),
        ("기본값", "Defaults"),
        ("타이머 창", "Timer Windows"),
        ("시계 창 보이기/숨기기", "Show/hide clock window"),
        ("고른 타이머 시작/일시정지", "Start/pause selected timer"),
        ("울림 끄기", "Stop ringing"),
        ("전체 목록 열기", "Open all timers & alarms"),
        ("등록하지 못함", "Couldn't register"),
        ("키를 누르세요", "Press keys"),
        ("없음", "None"),
        ("단축키 지우기", "Clear shortcut"),
        ("Esc를 누르면 입력을 취소해요.", "Press Esc to cancel."),
        ("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.", "Include ⌘, ⌃, or ⌥."),
        ("%@에서 쓰는 단축키예요.", "Already used for %@."),
        // 캘린더
        ("캘린더", "Calendar"),
        ("캘린더 일정", "Calendar Events"),
        ("일시", "When"),
        ("캘린더 연결…", "Connect Calendar…"),
        ("캘린더 추가…", "Add Calendar…"),
        ("iCal 주소 (구글 캘린더 개인 계정 등)", "iCal Addresses (personal Google Calendar, etc.)"),
        ("Mac 캘린더 앱 (회사 구글 계정 등)", "Mac Calendar App (work Google accounts, etc.)"),
        ("Mac 캘린더 앱의 일정으로 알림", "Alert for Mac Calendar events"),
        ("Mac 캘린더 앱에 캘린더가 없어요. 인터넷 계정에서 구글 계정을 추가하세요.", "The Calendar app has no calendars. Add your Google account in Internet Accounts."),
        ("이 Mac", "On My Mac"),
        ("고른 캘린더의 이틀 안 일정 %d개", "%d events in the next 2 days from selected calendars"),
        ("캘린더 접근을 허용해야 일정을 읽을 수 있어요.", "Allow calendar access so Epp can read your events."),
        ("접근 허용…", "Allow Access…"),
        ("캘린더 접근이 허용되지 않았어요. 시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 Epp를 \"전체 접근\"으로 바꾸세요.", "Calendar access isn't allowed. In System Settings → Privacy & Security → Calendars, set Epp to \"Full Access\"."),
        ("시스템 설정 열기", "Open System Settings"),
        ("시스템 설정 → 인터넷 계정에 구글 계정을 추가하면 그 일정이 Mac 캘린더 앱으로 들어와요. Apple 계정은 필요 없어요.", "Add your Google account in System Settings → Internet Accounts and its events appear in the Calendar app. No Apple Account is needed."),
        ("인터넷 계정 열기", "Open Internet Accounts"),
        ("캘린더 추가", "Add Calendar"),
        ("연결한 캘린더가 없어요", "No calendars connected"),
        ("구글 캘린더 웹 → 설정 → 왼쪽에서 캘린더 고르기 → 캘린더 통합에서 \"iCal 형식의 비공개 주소\"를 복사해 붙여 넣어요.", "In Google Calendar on the web, open Settings → pick a calendar on the left → Integrate calendar, then copy \"Secret address in iCal format\" and paste it here."),
        ("회사·학교 계정은 관리자가 비공개 주소를 막아 두어 이 항목이 없을 수 있어요. 그럴 때는 위의 Mac 캘린더 앱 연동을 쓰거나, 이미 공개해 둔 캘린더라면 \"iCal 형식의 공개 주소\"를 넣어도 돼요.", "Work and school accounts may not show this item if an administrator turned off secret addresses. In that case use the Mac Calendar app option above, or, if the calendar is already public, paste its \"Public address in iCal format\"."),
        ("구글 캘린더 웹 → 설정 → 왼쪽에서 캘린더 고르기 → 캘린더 통합 → \"iCal 형식의 비공개 주소\"를 복사해 붙여 넣어요. 이 주소를 아는 사람은 일정을 볼 수 있으니 다른 곳에 올리지 마세요.", "In Google Calendar on the web, open Settings → pick a calendar on the left → Integrate calendar → copy \"Secret address in iCal format\" and paste it here. Anyone with this address can see your events, so don't share it."),
        ("알림", "Alert"),
        ("일정 시작할 때", "At start time"),
        ("%d분 전", "%d min before"),
        ("종일 일정에도 알림", "Alert for all-day events"),
        ("거절한 일정에도 알림", "Alert for declined events"),
        ("지금 새로 받기", "Refresh Now"),
        ("15분마다, 그리고 Mac이 깨어날 때 새로 받아요. Mac을 쓰는 동안(Epp가 켜져 있고 잠자기 중이 아닐 때) 울려요.", "Epp refreshes every 15 minutes and when your Mac wakes. Alerts ring while you're using your Mac (Epp running, not asleep)."),
        ("%@ · 이틀 안 일정 %d개", "%@ · %d events in the next 2 days"),
        ("이 캘린더 빼기", "Remove This Calendar"),
        ("%@ 빼기", "Remove %@"),
        ("아직 받지 않았어요", "Not refreshed yet"),
        ("마지막으로 받은 시각 %@", "Last refreshed %@"),
        ("주소가 올바르지 않아요.", "This address isn't valid."),
        ("https:// 또는 webcal:// 로 시작하는 주소만 넣을 수 있어요.", "Only addresses starting with https:// or webcal:// are allowed."),
        ("이미 넣은 주소예요.", "This address is already added."),
        ("주소를 찾을 수 없어요. 비공개 주소를 다시 복사해 주세요.", "Address not found. Copy the secret address again."),
        ("서버 응답 %d", "Server returned %d"),
        ("iCal 형식이 아니에요.", "Not in iCal format."),
        ("(제목 없음)", "(No title)"),
        ("설정 → 캘린더에서 구글 캘린더를 연결하세요", "Connect Google Calendar in Settings → Calendar"),
        ("이틀 안에 일정이 없어요", "No events in the next 2 days"),
        ("이번 알림 끄기", "Skip This Alert"),
        ("이번 알림 켜기", "Turn This Alert Back On"),
        ("%@ 알림 끄기", "Skip alert for %@"),
        ("%@ 알림 켜기", "Turn on alert for %@"),
        ("이번 일정 알림", "Alert for this event"),
        ("끔", "Off"),
        ("%@ · 지남", "%@ · passed"),
        ("%@ · 울림", "%@ · Ringing"),
        ("%@ · %@ · 알림 끔", "%@ · %@ · alert off"),
        ("%@ · %@ · 알림 지남", "%@ · %@ · alert passed"),
        ("%@ · %@ · 알림까지 %@", "%@ · %@ · alert in %@"),
        ("📅 %@ · %@ 시작 (알림까지 %@)", "📅 %@ · starts %@ (alert in %@)"),
        ("일정은 구글 캘린더에서 고쳐요. 알림 시점은 설정 → 캘린더에서 바꿔요.", "Edit events in Google Calendar. Change when alerts ring in Settings → Calendar."),
        // 업데이트
        ("닫기", "Close"),
        ("파일이 너무 커요.", "The file is too large."),
        ("휴지통으로 옮기기", "Move to Trash"),
        // 설치 위치
        // 잠자기·놓친 알림·소리 꺼짐
        ("곧 울릴 것이 있으면 Mac이 잠들지 않게", "Keep Mac awake when something will ring soon"),
        ("타이머가 도는 동안과 알람·일정이 10분 안에 울릴 때 Mac이 저절로 잠들지 않게 해요. 화면은 꺼질 수 있어요. 덮개를 닫으면 잠들어서 울리지 않아요.", "While a timer runs, or an alarm or event will ring within 10 minutes, your Mac won't go to sleep on its own. The display can still turn off. If you close the lid, your Mac sleeps and Epp can't ring."),
        ("놓친 알림", "Missed"),
        ("놓친 알림 확인", "Dismiss Missed Alerts"),
        ("⚠︎ 놓친 알림: %@ · %@", "⚠︎ Missed: %@ · %@"),
        ("Mac이 잠들었거나 Epp가 꺼져 있어서 울리지 못했어요.", "Your Mac was asleep or Epp was quit, so these didn't ring."),
        ("🔇 Mac 소리가 꺼져 있어 알람이 들리지 않아요", "🔇 Your Mac's sound is off, so alarms won't be heard"),
        ("Mac 소리가 꺼져 있어 알람이 들리지 않아요", "Your Mac's sound is off, so alarms won't be heard"),
        ("확인", "OK"),
        ("어제", "yesterday"),
        // 편집 메뉴
    ]
}

/// 화면 문구. 한국어 문구를 그대로 넘기면 Epp 언어로 돌려준다. `%@`, `%ld` 등은 args로 채운다.
func L(_ korean: String, _ args: CVarArg...) -> String {
    Localization.translations.text(korean, args)
}
