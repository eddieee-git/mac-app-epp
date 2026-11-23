import AppKit
import EppKit
import SwiftUI
import UniformTypeIdentifiers

/// Epp 설정 창에서 타이머를 골랐을 때의 탭: 일반 · 타이머·알람 · 소리 · 캘린더 · 단축키.
/// 틀(머리·시작하기·탭·검색)은 Epp 본체가 그린다. 언어, 로그인 시 실행, 업데이트, 정보는 Epp 일반 쪽에 있다.
enum ClockySettingsTabs {
    @MainActor
    static func tabs(settings: ClockySettings, calendar: CalendarSync) -> [EppSettingsTab] {
        func view(_ tab: SettingsView.Tab) -> SettingsView { SettingsView(settings: settings, calendar: calendar, tab: tab) }
        return [
            EppSettingsTab("general", L("일반"), keywords: [L("삭제하기 전에 확인"), L("메뉴바"), L("타이머 남은 시간 표시"),
                                                          L("1시간 안에 울릴 알람까지 남은 시간 표시"), L("Epp 아이콘과 따로 보이기")]) { view(.general) },
            EppSettingsTab("clock", L("타이머·알람"), keywords: [L("타이머 버튼(분)")]) { view(.clock) },
            EppSettingsTab("sound", L("소리"), keywords: [L("소리")]) { view(.sound) },
            EppSettingsTab("calendar", L("캘린더"), keywords: [L("캘린더")]) { view(.calendar) },
            EppSettingsTab("shortcuts", L("단축키"), keywords: [L("전역 단축키"), L("시계 창")]) { view(.shortcuts) },
        ]
    }
}


struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general = "일반"
        case clock = "타이머·알람"
        case sound = "소리"
        case calendar = "캘린더"
        case shortcuts = "단축키"
    }

    @ObservedObject var settings: ClockySettings
    @ObservedObject var calendar: CalendarSync
    let tab: Tab

    init(settings: ClockySettings, calendar: CalendarSync, tab: Tab) {
        self.settings = settings
        self.calendar = calendar
        self.tab = tab
    }

    var body: some View {
        switch tab {
        case .general: general
        case .clock: clock
        case .sound: sound
        case .calendar: CalendarSettings(settings: settings, sync: calendar)
        case .shortcuts: shortcuts
        }
    }

    private var general: some View {
        Form {
            Section {
                Toggle(L("삭제하기 전에 확인"), isOn: $settings.confirmDelete)
            }
            Section {
                Toggle(L("타이머 남은 시간 표시"), isOn: $settings.menuBarShowsTimer)
                Toggle(L("1시간 안에 울릴 알람까지 남은 시간 표시"), isOn: $settings.menuBarShowsAlarm)
                Toggle(L("Epp 아이콘과 따로 보이기"), isOn: $settings.menuBarSeparateItem)
            } header: {
                Text(L("메뉴바"))
            } footer: {
                Text(L("끄면 남은 시간이 Epp 아이콘 바로 옆에 붙어서 메뉴바 아이콘이 늘지 않아요. 켜면 따로 생긴 항목을 눌러 타이머 메뉴를 바로 열 수 있어요."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var clock: some View {
        Form {
            Section {
                Picker(L("미리 깜빡이기"), selection: $settings.warningSeconds) {
                    ForEach(ClockySettings.warningChoices, id: \.self) {
                        Text($0 == 0 ? L("깜빡이지 않음") : L("%d초 전부터", $0)).tag($0)
                    }
                }
                Picker(L("다시 울림 간격"), selection: $settings.snoozeMinutes) {
                    ForEach(ClockySettings.snoozeChoices, id: \.self) { Text(L("%d분", $0)).tag($0) }
                }
                Picker(L("소리를 되풀이하는 시간"), selection: $settings.soundLimitSeconds) {
                    ForEach(ClockySettings.soundLimitChoices, id: \.self) {
                        Text($0 < 60 ? L("%d초", $0) : L("%d분", $0 / 60)).tag($0)
                    }
                }
                Toggle(L("곧 울릴 것이 있으면 Mac이 잠들지 않게"), isOn: $settings.keepMacAwake)
            } footer: {
                Text(L("소리가 멈춘 뒤에도 끌 때까지 창은 깜빡여요.") + "\n" + L("타이머가 도는 동안과 알람·일정이 10분 안에 울릴 때 Mac이 저절로 잠들지 않게 해요. 화면은 꺼질 수 있어요. 덮개를 닫으면 잠들어서 울리지 않아요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                PresetEditor(settings: settings)
            } footer: {
                Text(L("시계 창과 목록 창의 시간 버튼이에요. 분 단위로 쉼표를 넣어 적고 Return을 눌러요. 6개까지 써요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var sound: some View {
        Form {
            Section {
                HStack {
                    SoundPicker(title: L("알람 소리"), selection: $settings.alarmSound, choices: soundChoices)
                    Button { AlarmSound.play() } label: { Image(systemName: "play.fill") }
                        .help(L("들어 보기"))
                        .accessibilityLabel(L("들어 보기"))
                }
                HStack {
                    Spacer()
                    if settings.alarmSound.hasPrefix(AlarmSound.filePrefix) {
                        Button(L("이 파일 지우기")) { removeCustomSound() }
                    }
                    Button(L("내 소리 파일 추가…")) { importSound() }
                }
                LabeledContent(L("소리 크기")) {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $settings.soundVolume, in: 0...1) { editing in
                            if !editing { AlarmSound.play() }
                        }
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(L("Mac의 소리를 꺼 두면 알람도 들리지 않아요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.alarmSound) { _ in AlarmSound.play() }
    }

    /// 파일을 더하거나 지우면 목록을 다시 읽는다.
    @State private var soundChoices = AlarmSound.choices

    private func importSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = L("알람으로 쓸 소리 파일을 고르세요. Epp 폴더로 복사해 둬요.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let id = AlarmSound.importFile(url) {
            soundChoices = AlarmSound.choices
            settings.alarmSound = id
        } else {
            let alert = NSAlert()
            alert.messageText = L("이 파일은 소리로 열 수 없어요.")
            alert.runModal()
        }
    }

    private func removeCustomSound() {
        let id = settings.alarmSound
        settings.alarmSound = AlarmSound.defaultName
        AlarmSound.removeFile(id)
        soundChoices = AlarmSound.choices
    }

    /// 위는 바꿀 수 있는 전역 단축키, 아래는 창 안에서 쓰는 키 안내.
    private var shortcuts: some View {
        Form {
            Section {
                HotKeyEditor(settings: settings)
            } header: {
                Text(L("전역 단축키"))
            } footer: {
                Text(EppShortcutText.footer).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("시계 창")) {
                shortcut("스페이스", "고른 타이머 시작·일시정지, 고른 알람 켜기·끄기")
                shortcut("↑ ↓", "목록에서 고르기")
                shortcut("⌘N", "타이머 또는 알람 추가")
                shortcut("⌘⌫", "고른 항목 지우기")
                shortcut("⌘Z  ⇧⌘Z", "지운 항목 되살리기, 다시 지우기")
                shortcut("⌘1  ⌘2", "타이머, 알람")
                shortcut("Esc", "울림 끄기, 이름 편집 끝내기")
                shortcut("S", "울리는 동안 다시 울림")
            }
            Section(L("타이머 창")) {
                shortcut("⌘L", "타이머 목록")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        LabeledContent(L(action)) {
            Text(L(keys)).monospaced().foregroundStyle(.secondary)
        }
    }
}

/// 시스템 소리와 내 소리 파일을 한 메뉴에서 고른다.
struct SoundPicker<Tag: Hashable>: View {
    let title: String
    @Binding var selection: Tag
    let choices: [String]
    /// 목록 창의 알람처럼 "기본 소리"를 맨 위에 둘 때.
    var defaultOption: (label: String, tag: Tag)?
    var tag: (String) -> Tag = { $0 as! Tag }

    var body: some View {
        Picker(title, selection: $selection) {
            if let defaultOption {
                Text(defaultOption.label).tag(defaultOption.tag)
                Divider()
            }
            ForEach(choices.filter { !$0.hasPrefix(AlarmSound.filePrefix) }, id: \.self) { Text(AlarmSound.title($0)).tag(tag($0)) }
            let files = choices.filter { $0.hasPrefix(AlarmSound.filePrefix) }
            if !files.isEmpty {
                Divider()
                ForEach(files, id: \.self) { Text(AlarmSound.title($0)).tag(tag($0)) }
            }
        }
    }
}

/// 타이머 시간 버튼을 "1, 3, 5, 10, 25"처럼 적어 바꾼다.
private struct PresetEditor: View {
    @ObservedObject var settings: ClockySettings
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        LabeledContent(L("타이머 버튼(분)")) {
            HStack {
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
                    .onSubmit(apply)
                    .foregroundStyle(invalid ? Color.red : Color.primary)
                Button(L("기본값")) {
                    settings.timerPresets = ClockySettings.defaultPresets
                    load()
                }
                .disabled(settings.timerPresets == ClockySettings.defaultPresets)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        text = settings.timerPresets.map(String.init).joined(separator: ", ")
        invalid = false
    }

    private func apply() {
        guard let presets = ClockySettings.parsePresets(text) else {
            invalid = true
            NSSound.beep()
            return
        }
        settings.timerPresets = presets
        load()
    }
}

/// 전역 단축키를 바꾼다. 버튼을 누른 뒤 새 조합을 누르면 바로 등록된다.
private struct HotKeyEditor: View {
    @ObservedObject var settings: ClockySettings

    var body: some View {
        ForEach(HotKeyAction.allCases, id: \.self) { action in
            EppShortcutRow(action.title,
                           combo: Binding(get: { settings.hotKeys[action.rawValue] }, set: { settings.hotKeys[action.rawValue] = $0 }),
                           defaultCombo: KeyCombo.defaults[action.rawValue],
                           failed: settings.failedHotKeys.contains(action)) { combo in
                HotKeyAction.allCases.first { $0 != action && settings.hotKeys[$0.rawValue] == combo }
                    .map { L("%@에서 쓰는 단축키예요.", $0.title) }
            }
        }
        HStack {
            Text(L("Esc를 누르면 입력을 취소해요.")).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L("기본값으로")) { settings.hotKeys = KeyCombo.defaults }
        }
    }
}

/// 구글 캘린더 비공개 iCal 주소를 넣고, 언제 울릴지와 어떤 일정을 뺄지 정한다.
private struct CalendarSettings: View {
    @ObservedObject var settings: ClockySettings
    @ObservedObject var sync: CalendarSync

    var body: some View {
        Form {
            MacCalendarSection(settings: settings, sync: sync, mac: sync.mac)
            Section {
                ForEach(settings.calendarFeeds) { feed in
                    feedRow(feed)
                }
                if settings.calendarFeeds.isEmpty {
                    Text(L("연결한 캘린더가 없어요"))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    // 주소는 길어서 줄 안의 칸보다 따로 뜨는 창에서 넣는 편이 보기 쉽다.
                    Button(L("캘린더 추가…")) { CalendarAddPrompt.run(sync: sync) }
                }
            } header: {
                Text(L("iCal 주소 (구글 캘린더 개인 계정 등)"))
            } footer: {
                Text(L("구글 캘린더 웹 → 설정 → 왼쪽에서 캘린더 고르기 → 캘린더 통합 → \"iCal 형식의 비공개 주소\"를 복사해 붙여 넣어요. 이 주소를 아는 사람은 일정을 볼 수 있으니 다른 곳에 올리지 마세요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(L("알림"), selection: $settings.calendarLeadMinutes) {
                    ForEach(ClockySettings.calendarLeadChoices, id: \.self) {
                        Text($0 == 0 ? L("일정 시작할 때") : L("%d분 전", $0)).tag($0)
                    }
                }
                Toggle(L("종일 일정에도 알림"), isOn: $settings.calendarIncludeAllDay)
                Toggle(L("거절한 일정에도 알림"), isOn: $settings.calendarIncludeDeclined)
                HStack {
                    Text(lastRefreshText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if sync.isRefreshing { ProgressView().controlSize(.small) }
                    Button(L("지금 새로 받기")) { sync.refresh() }
                        .disabled(sync.isRefreshing || !settings.calendarFeeds.contains(where: \.enabled))
                }
            } footer: {
                Text(L("15분마다, 그리고 Mac이 깨어날 때 새로 받아요. Mac을 쓰는 동안(Epp가 켜져 있고 잠자기 중이 아닐 때) 울려요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func feedRow(_ feed: CalendarFeed) -> some View {
        let status = sync.statuses[feed.id]
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { settings.calendarFeeds.first { $0.id == feed.id }?.enabled ?? false },
                                     set: { value in
                                         if let i = settings.calendarFeeds.firstIndex(where: { $0.id == feed.id }) {
                                             settings.calendarFeeds[i].enabled = value
                                         }
                                     }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(L("%@ 켜기", sync.title(of: feed)))
            VStack(alignment: .leading, spacing: 2) {
                Text(sync.title(of: feed)).lineLimit(1)
                Group {
                    if let error = status?.error {
                        Text(error).foregroundStyle(.red)
                    } else if status?.lastSuccess != nil {
                        Text(L("%@ · 이틀 안 일정 %d개", feed.maskedURL, status?.eventCount ?? 0))
                    } else {
                        Text(feed.maskedURL)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Button {
                sync.remove(feed.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(L("이 캘린더 빼기"))
            .accessibilityLabel(L("%@ 빼기", sync.title(of: feed)))
        }
    }

    private var lastRefreshText: String {
        let dates = settings.calendarFeeds.compactMap { sync.statuses[$0.id]?.lastSuccess }
        guard let last = dates.max() else { return L("아직 받지 않았어요") }
        return L("마지막으로 받은 시각 %@", settings.timeText(last))
    }

}

/// "캘린더 추가…"를 누르면 뜨는 창. 클립보드에 iCal 주소가 있으면 미리 채운다.
/// 주소가 틀렸으면 이유를 보여 주고 고칠 수 있게 다시 띄운다.
enum CalendarAddPrompt {
    static func run(sync: CalendarSync, initial: String? = nil, problem: String? = nil) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = "https://calendar.google.com/calendar/ical/…/basic.ics"
        field.stringValue = initial ?? clipboardAddress() ?? ""
        field.lineBreakMode = .byTruncatingMiddle

        let alert = NSAlert()
        alert.messageText = L("캘린더 추가")
        var info = L("구글 캘린더 웹 → 설정 → 왼쪽에서 캘린더 고르기 → 캘린더 통합에서 \"iCal 형식의 비공개 주소\"를 복사해 붙여 넣어요.")
        info += "\n\n" + L("회사·학교 계정은 관리자가 비공개 주소를 막아 두어 이 항목이 없을 수 있어요. 그럴 때는 위의 Mac 캘린더 앱 연동을 쓰거나, 이미 공개해 둔 캘린더라면 \"iCal 형식의 공개 주소\"를 넣어도 돼요.")
        if let problem { info = problem + "\n\n" + info }
        alert.informativeText = info
        alert.accessoryView = field
        alert.addButton(withTitle: L("추가"))
        alert.addButton(withTitle: L("취소"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let text = field.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch sync.add(text) {
        case nil:
            break
        case .invalid?:
            run(sync: sync, initial: text, problem: L("주소가 올바르지 않아요."))
        case .notSecure?:
            run(sync: sync, initial: text, problem: L("https:// 또는 webcal:// 로 시작하는 주소만 넣을 수 있어요."))
        case .duplicate?:
            run(sync: sync, initial: text, problem: L("이미 넣은 주소예요."))
        }
    }

    /// 클립보드에 iCal 주소처럼 보이는 글이 있으면.
    static func clipboardAddress() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count < 2000, !text.contains("\n") else { return nil }
        let lower = text.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("webcal://") else { return nil }
        return lower.contains("ical") || lower.hasSuffix(".ics") ? text : nil
    }
}

/// Mac 캘린더 앱 경유. 회사 구글 계정처럼 비공개 iCal 주소를 쓸 수 없을 때 쓴다.
private struct MacCalendarSection: View {
    @ObservedObject var settings: ClockySettings
    @ObservedObject var sync: CalendarSync
    @ObservedObject var mac: MacCalendarSource

    var body: some View {
        Section {
            Toggle(L("Mac 캘린더 앱의 일정으로 알림"), isOn: $settings.macCalendarEnabled)
            if settings.macCalendarEnabled {
                switch mac.access {
                case .granted:
                    if mac.calendars.isEmpty {
                        Text(L("Mac 캘린더 앱에 캘린더가 없어요. 인터넷 계정에서 구글 계정을 추가하세요."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(accounts, id: \.self) { account in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.isEmpty ? L("이 Mac") : account)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(mac.calendars.filter { $0.account == account }) { calendar in
                                Toggle(isOn: binding(for: calendar.id)) {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(nsColor: calendar.color)).frame(width: 9, height: 9)
                                        Text(calendar.title)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    Text(L("고른 캘린더의 이틀 안 일정 %d개", sync.macEventCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .notDetermined:
                    HStack {
                        Text(L("캘린더 접근을 허용해야 일정을 읽을 수 있어요."))
                        Spacer()
                        Button(L("접근 허용…")) { mac.requestAccess { sync.recompute() } }
                    }
                case .denied, .writeOnly, .restricted:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("캘린더 접근이 허용되지 않았어요. 시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 Epp를 \"전체 접근\"으로 바꾸세요."))
                            .foregroundStyle(.red)
                        Button(L("시스템 설정 열기")) { MacCalendarSource.openPrivacySettings() }
                    }
                }
            }
        } header: {
            Text(L("Mac 캘린더 앱 (회사 구글 계정 등)"))
        } footer: {
            HStack(alignment: .top) {
                Text(L("시스템 설정 → 인터넷 계정에 구글 계정을 추가하면 그 일정이 Mac 캘린더 앱으로 들어와요. Apple 계정은 필요 없어요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("인터넷 계정 열기")) { MacCalendarSource.openInternetAccounts() }
                    .controlSize(.small)
            }
        }
        .onAppear {
            // 시스템 설정에서 허용을 바꾸고 돌아왔을 수 있다.
            if settings.macCalendarEnabled { mac.requestAccess { sync.recompute() } }
        }
    }

    private var accounts: [String] {
        var seen: [String] = []
        for calendar in mac.calendars where !seen.contains(calendar.account) { seen.append(calendar.account) }
        return seen
    }

    /// 처음에는 모든 캘린더를 켠 상태(nil)로 두고, 하나라도 끄면 켠 것만 저장한다.
    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.macCalendarIDs.map { $0.contains(id) } ?? true },
            set: { isOn in
                var ids = Set(settings.macCalendarIDs ?? mac.calendars.map(\.id))
                if isOn { ids.insert(id) } else { ids.remove(id) }
                settings.macCalendarIDs = ids.count == mac.calendars.count ? nil : mac.calendars.map(\.id).filter(ids.contains)
            })
    }
}

