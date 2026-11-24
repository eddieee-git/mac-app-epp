import EppKit
import ServiceManagement
import SwiftUI

/// 설정 창에서 지금 보여 줄 쪽. "general" 또는 기능 id.
@MainActor
final class SettingsRouter: ObservableObject {
    static let general = "general"
    @Published var page: String = SettingsRouter.general

    /// 기능 쪽을 열고, tab이 있으면 그 탭을 고른다(페이지가 기억하는 탭 값을 바꾼다).
    func go(page: String, tab: String?) {
        if let tab { UserDefaults.standard.set(tab, forKey: EppSettingsKeys.tab(page)) }
        self.page = page
    }
}

/// 설정 검색 결과 한 줄: 어느 쪽·탭의 어떤 설정인지.
struct SettingsSearchResult: Identifiable {
    let page: String
    let tab: String?
    let title: String
    /// "Keepy › 일반"처럼 위치
    let place: String
    var id: String { "\(page)|\(tab ?? "")|\(title)" }
}

@MainActor
final class SettingsWindowController {
    private let manager: ModuleManager
    private let router = SettingsRouter()
    private var window: NSWindow?

    init(manager: ModuleManager) {
        self.manager = manager
        if let solo = manager.soloID { router.page = solo }
    }

    /// page: 기능 id. nil이면 마지막에 보던 쪽 그대로.
    func show(page: String?) {
        if let page { router.page = page }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(manager: manager, router: router))
            let w = EscClosableWindow(contentViewController: controller)
            // 시스템 설정과 같은 창 모양: 왼쪽 목록이 제목 막대까지 올라가고, 오른쪽 위에 고른 쪽 이름이 나온다.
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.title = L("Epp 설정")
            w.setContentSize(NSSize(width: SettingsView.size.width, height: SettingsView.size.height))
            EppWindows.prepare(w, autosaveName: "Settings", resizable: false)
            w.styleMask.remove(.miniaturizable)
            window = w
        }
        EppWindows.show(window)
    }
}

/// 왼쪽: 검색 + 일반 + 기능 목록, 오른쪽: 고른 쪽의 설정.
private struct SettingsView: View {
    static let size = CGSize(width: 720, height: 660)

    @ObservedObject var manager: ModuleManager
    @ObservedObject var router: SettingsRouter
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    pageList
                } else {
                    resultList
                }
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(pageTitle)
                // 시스템 설정처럼 불투명한 기본 창 배경. 비치는 배경은 바탕화면 색(남색 등)이 묻어난다.
                .background(Color(nsColor: .windowBackgroundColor))
        }
        // 시스템 설정과 같은 자리(왼쪽 목록 위)의 검색창
        .searchable(text: $query, placement: .sidebar, prompt: L("설정 검색"))
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// 오른쪽 위 제목: 고른 쪽 이름
    private var pageTitle: String {
        if router.page == SettingsRouter.general { return L("일반") }
        return ModuleList.infos.first { $0.id == router.page }?.name ?? L("Epp 설정")
    }

    private var pageList: some View {
        List(selection: $router.page) {
            Label(L("일반"), systemImage: "gearshape").tag(SettingsRouter.general)
            Section(L("기능")) {
                ForEach(visibleInfos) { info in
                    HStack {
                        Label(info.name, systemImage: info.symbol)
                        Spacer()
                        if !manager.isEnabled(info.id) {
                            Text(L("꺼짐")).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .tag(info.id)
                }
            }
        }
    }

    private var resultList: some View {
        let results = search(query)
        return List {
            if results.isEmpty {
                Text(L("찾는 설정이 없어요")).foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                Button {
                    router.go(page: result.page, tab: result.tab)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.title).lineLimit(2)
                        Text(result.place).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .background(router.page == result.page ? Color.accentColor.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private var visibleInfos: [EppModuleInfo] {
        if let solo = manager.soloID { return ModuleList.infos.filter { $0.id == solo } }
        return ModuleList.infos
    }

    /// 본체 일반 쪽 + 기능마다(켜진 기능은 탭의 keywords까지)에서 찾는다.
    private func search(_ text: String) -> [SettingsSearchResult] {
        let q = text.trimmingCharacters(in: .whitespaces)
        var results: [SettingsSearchResult] = []
        func add(_ title: String, page: String, tab: String?, place: String) {
            guard title.localizedCaseInsensitiveContains(q) || place.localizedCaseInsensitiveContains(q),
                  !results.contains(where: { $0.page == page && $0.tab == tab && $0.title == title }) else { return }
            results.append(.init(page: page, tab: tab, title: title, place: place))
        }
        if manager.soloID == nil {
            for word in GeneralPage.keywords { add(word, page: SettingsRouter.general, tab: nil, place: L("일반")) }
        }
        for info in visibleInfos {
            add(info.name, page: info.id, tab: nil, place: info.summary)
            guard let module = manager.module(id: info.id) else { continue }
            for tab in module.settingsTabs() {
                let place = "\(info.name) › \(tab.title)"
                add(tab.title, page: info.id, tab: tab.id, place: place)
                for word in tab.keywords { add(word, page: info.id, tab: tab.id, place: place) }
            }
        }
        return results
    }

    /// 이 기능의 전역 단축키 중 켠 다른 기능과 같은 키. 그 기능의 단축키 탭 위에 알린다.
    static func shortcutClashes(of id: String, manager: ModuleManager) -> [String] {
        guard let mine = manager.module(id: id)?.globalShortcuts(), !mine.isEmpty else { return [] }
        var others = manager.enabledTypes.filter { $0.info.id != id }.flatMap { type in
            (manager.module(id: type.info.id)?.globalShortcuts() ?? []).map { (type.info.name, $0) }
        }
        if let combo = QuickSearch.combo {
            others.append(("Epp", EppShortcutInfo(title: L("빠른 검색 열기"), keys: combo.displayText)))
        }
        return mine.flatMap { shortcut in
            others.filter { $0.1.keys == shortcut.keys }.map { name, other in
                L("\"%@\" (%@) — %@의 \"%@\"와 같은 키예요. 먼저 등록한 기능만 동작해요.",
                  shortcut.title, shortcut.keys, name, other.title)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if router.page == SettingsRouter.general {
            GeneralPage(manager: manager, router: router)
        } else if let info = ModuleList.infos.first(where: { $0.id == router.page }) {
            if let module = manager.module(id: info.id) {
                EppSettingsPage(info: info, tabs: module.settingsTabs(), gettingStarted: module.makeGettingStarted(),
                                shortcutClashes: { [manager] in Self.shortcutClashes(of: info.id, manager: manager) })
                    .id(info.id)
            } else {
                DisabledModulePage(info: info) { manager.setEnabled(info.id, true) }
            }
        }
    }
}

/// 꺼진 기능을 골랐을 때
private struct DisabledModulePage: View {
    let info: EppModuleInfo
    let enable: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: info.symbol).font(.system(size: 40)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(info.name).font(.title2.bold())
            Text(info.summary).foregroundStyle(.secondary)
            Text(L("%@가 꺼져 있어요. 켜면 설정이 여기에 나와요.", info.name)).font(.callout).foregroundStyle(.secondary)
            Button(L("%@ 켜기", info.name), action: enable).keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 일반

private struct GeneralPage: View {
    /// 설정 검색에서 이 쪽을 찾게 할 설정 이름들
    static var keywords: [String] {
        [L("기능"), L("모두 켜기"), L("권한"), EppPermission.accessibility.title, EppPermission.screenRecording.title,
         L("빠른 검색"), L("빠른 검색 열기"), L("로그인 시 실행"), L("Dock에 아이콘 보이기"), L("테마"), L("언어"),
         L("업데이트"), L("문제 해결"), L("진단 로그 남기기"), L("데이터 폴더"), L("설정 옮기기"), L("설정 내보내기…"), L("설정 가져오기…"), L("정보")]
    }

    @ObservedObject var manager: ModuleManager
    let router: SettingsRouter
    @ObservedObject private var permissions = EppPermissions.shared
    @AppStorage(EppLog.enabledKey) private var diagnosticLog = false
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showInDock = DockIcon.isOn
    @State private var theme = EppAppTheme.current
    /// "system" | "ko" | "en". 문구는 시작할 때 한 번 정해지므로 바꾸면 다시 열어야 한다.
    @State private var language = UserDefaults.standard.string(forKey: EppLanguage.key) ?? "system"
    private let launchLanguage = UserDefaults.standard.string(forKey: EppLanguage.key) ?? "system"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        Form {
            Section {
                if manager.enabledIDs.isEmpty && manager.soloID == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Epp에 오신 걸 환영해요")).font(.headline)
                        Text(L("아래에서 쓸 기능을 켜세요. 여러 개를 한꺼번에 켜도 돼요. 켠 기능은 왼쪽 목록에 나오고, 처음 열면 시작하기가 하나씩 안내해요."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(ModuleList.infos) { info in
                    HStack {
                        Toggle(isOn: Binding(get: { manager.isEnabled(info.id) },
                                             set: { manager.setEnabled(info.id, $0, showSettings: false) })) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(info.name)
                                    Text(info.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: info.symbol)
                            }
                        }
                        .disabled(manager.soloID != nil)
                        if manager.isEnabled(info.id) && manager.soloID == nil {
                            Button(L("설정 열기")) { router.go(page: info.id, tab: nil) }
                                .buttonStyle(.link)
                                .help(L("%@ 설정과 시작하기를 열어요.", info.name))
                        }
                    }
                }
            } header: {
                HStack {
                    Text(L("기능"))
                    Spacer()
                    if manager.soloID == nil {
                        Button(manager.allEnabled ? L("모두 끄기") : L("모두 켜기")) {
                            manager.setAllEnabled(!manager.allEnabled)
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            } footer: {
                Text(manager.soloID != nil
                     ? L("단독 실행 중이라 이 기능만 켜져 있어요.")
                     : L("켠 기능만 실행돼요. 끈 기능은 아무 일도 하지 않고, 단축키도 등록하지 않아요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            permissionSection

            Section {
                EppShortcutRow(L("빠른 검색 열기"), combo: Binding(get: { QuickSearch.combo }, set: { QuickSearch.combo = $0 }),
                               defaultCombo: QuickSearch.defaultCombo)
            } header: {
                Text(L("빠른 검색"))
            } footer: {
                Text(L("켠 기능의 내용(클립보드 기록, 스티커, 캡처 속 글자, 타이머·알람)을 한 번에 찾아요. 잠근 스티커는 찾지 않아요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("로그인 시 실행"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L("Dock에 아이콘 보이기"), isOn: $showInDock)
                        .onChange(of: showInDock) { _, on in DockIcon.isOn = on }
                    Text(L("켜면 Dock에 Epp가 보이고, 메뉴 막대 왼쪽에 Epp 메뉴가 나와요. 메뉴 막대 아이콘은 그대로 있어요."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker(L("테마"), selection: Binding(get: { theme }, set: { theme = $0; EppAppTheme.current = $0 })) {
                    ForEach(EppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(L("언어"), selection: $language) {
                    Text(L("시스템 설정 따르기")).tag("system")
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
                .onChange(of: language) { _, new in
                    if new == "system" { UserDefaults.standard.removeObject(forKey: EppLanguage.key) }
                    else { UserDefaults.standard.set(new, forKey: EppLanguage.key) }
                }
                if language != launchLanguage {
                    HStack {
                        Text(L("언어를 바꾸면 Epp를 다시 열어야 적용돼요.")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Epp 다시 열기")) { EppApp.relaunch() }
                    }
                }
            }

            Section {
                Toggle(L("진단 로그 남기기"), isOn: $diagnosticLog)
                    .onChange(of: diagnosticLog) { _, on in if !on { EppLog.clear() } }
                if diagnosticLog {
                    Button(L("로그 파일 보기")) {
                        NSWorkspace.shared.selectFile(EppLog.path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.link)
                }
                LabeledContent(L("데이터 폴더")) {
                    Button(L("Finder에서 보기")) {
                        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent(ModuleManager.folderName, isDirectory: true)
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
            } header: {
                Text(L("문제 해결"))
            } footer: {
                Text(L("진단 로그는 권한·동작 문제를 찾을 때만 켜요. 모든 기능이 한 파일(~/Library/Logs)에 적고, 복사한 내용 같은 개인 내용은 적지 않아요. 끄면 파일을 지워요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L("설정 파일")) {
                    HStack {
                        Button(L("설정 내보내기…")) { SettingsBackup.exportWithPanel() }
                        Button(L("설정 가져오기…")) { SettingsBackup.importWithPanel() }
                    }
                }
            } header: {
                Text(L("설정 옮기기"))
            } footer: {
                Text(L("켠 기능·단축키·테마 같은 설정을 파일 하나로 옮겨요(새 Mac 등). 클립보드 기록·스티커·캡처 같은 내용은 들어가지 않아요. 내용은 위의 데이터 폴더를 복사해요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            AppUpdaterSection(updater: AppUpdater.shared)

            Section(L("정보")) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Epp").font(.headline)
                        Text(L("버전 %@", version)).foregroundStyle(.secondary)
                        Text(L("Mac을 편하게 쓰는 작은 기능 모음")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { permissions.refresh() }
        .onReceive(poll) { _ in permissions.refresh() }
    }

    /// 권한은 Epp 하나에 주는 것이라 여기 한 곳에서 다룬다. 켜진 기능이 쓰는 권한만, 어느 기능이 왜 쓰는지와 함께 보여 준다.
    @ViewBuilder private var permissionSection: some View {
        let used = EppPermission.allCases.compactMap { permission -> (EppPermission, [String], Bool)? in
            var reasons: [String] = []
            var required = false
            for type in manager.enabledTypes {
                for need in type.permissionNeeds where need.permission == permission {
                    reasons.append("\(type.info.name): \(need.reason)")
                    required = required || need.required
                }
            }
            return reasons.isEmpty ? nil : (permission, reasons, required)
        }
        Section {
            if used.isEmpty {
                Text(L("켠 기능 중에 권한이 필요한 기능이 없어요.")).foregroundStyle(.secondary)
            }
            ForEach(used, id: \.0) { permission, reasons, required in
                EppPermissionRow(title: permission.title + (required ? L(" (필수)") : L(" (선택)")),
                                 detail: reasons.joined(separator: "\n"),
                                 granted: permissions.isGranted(permission)) {
                    permissions.request(permission)
                } extra: {
                    if permission == .screenRecording {
                        Button(L("Epp 다시 열기")) { EppApp.relaunch() }
                            .help(L("화면 기록은 허용한 뒤 Epp를 다시 열어야 적용돼요."))
                    }
                }
            }
        } header: {
            Text(L("권한"))
        } footer: {
            Text(L("Mac은 권한을 Epp 하나에 줘요. 시스템 설정 → 개인정보 보호 및 보안에서 Epp를 켜면 모든 기능에 적용돼요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Epp: 로그인 항목 설정 실패 \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
