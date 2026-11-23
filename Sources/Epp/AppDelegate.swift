import AppKit
import EppKit
import UserNotifications

/// Dock에 Epp 아이콘을 보일지 (기본 끔). 바꾸면 바로 적용한다.
@MainActor
enum DockIcon {
    static let key = "showInDock"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
            // macOS는 실행 중에 정책이 바뀐 앱의 메뉴 막대를 바로 다시 그리지 않는다.
            // 다른 앱(Dock)을 잠깐 앞으로 했다가 Epp를 다시 앞으로 가져와서 메뉴 막대를 새로 그리게 한다.
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                bringToFront(window)
            }
        }
    }

    static func bringToFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let manager: ModuleManager
    private let settingsWindow: SettingsWindowController
    private var statusItem: NSStatusItem!
    private lazy var quickSearch = QuickSearch(manager: manager)

    init(manager: ModuleManager) {
        self.manager = manager
        settingsWindow = SettingsWindowController(manager: manager)
        super.init()
        manager.openSettings = { [weak self] id in self?.showSettings(page: id) }
        manager.hostStatusItems = { [weak self] in [self?.statusItem].compactMap { $0 } }
        manager.setStatusText = { [weak self] id, text in self?.setStatusText(text, for: id) }
        // 기능을 켜고 끌 때마다 기능이 더한 앱 메뉴(파일·서식 등)를 다시 모은다.
        manager.onChange = { [weak self] in self?.rebuildMainMenu() }
    }

    private var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunchedBefore") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunchedBefore") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EppLog.path = NSHomeDirectory() + "/Library/Logs/\(ModuleManager.folderName).log"
        EppLog.clear()
        EppLog.write("Epp", "launch \(Bundle.main.bundlePath) version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "-") features=\(manager.enabledIDs)")
        // 알림은 앱마다 처리기가 하나라 본체가 받아 보낸 기능에게 넘긴다.
        if EppNotifications.isAvailable { UNUserNotificationCenter.current().delegate = self }

        // 새 아이콘은 macOS가 왼쪽 끝(노치 쪽)에 놓아 가려질 수 있다. 처음 한 번만 오른쪽 가까이에 둔다.
        // 값은 오른쪽 끝에서 잰 거리. 사용자가 옮긴 뒤에는 macOS가 바꾼 값을 그대로 둔다.
        let positionKey = "NSStatusItem Preferred Position EppMain"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(170.0, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // 사용자가 ⌘로 끌어 옮긴 자리를 macOS가 기억하게 한다.
        statusItem.autosaveName = "EppMain"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        let solo = manager.soloID.flatMap(ModuleList.type(id:))?.info
        let image = NSImage(systemSymbolName: solo?.symbol ?? "square.grid.2x2", accessibilityDescription: solo?.name ?? "Epp")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = solo.map { "\($0.name) (Epp)" } ?? "Epp"

        EppAppTheme.apply()
        manager.startEnabled()
        if manager.soloID == nil {
            quickSearch.registerHotKey()
            NotificationCenter.default.addObserver(forName: QuickSearch.hotKeyChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.quickSearch.registerHotKey() }
            }
        }
        rebuildMainMenu()
        if AppUpdater.shouldRun { AppUpdater.shared.start() }

        #if DEBUG
        if let page = UserDefaults.standard.string(forKey: "openSettingsPage") {
            showSettings(page: page)
        }
        // -debugStatusText "⏰04:59" : 타이머처럼 Epp 아이콘 옆에 글을 붙여 본다.
        if let text = UserDefaults.standard.string(forKey: "debugStatusText") {
            setStatusText(text, for: "clocky")
        }
        // -debugQuickSearch "찾을 말" : 빠른 검색을 그 말로 띄운다(화면 확인용).
        if let text = UserDefaults.standard.string(forKey: "debugQuickSearch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.quickSearch.show(query: text) }
        }
        // -debugCryptoCheck <account> : 그 이름으로 키를 만들어 암호화·풀기를 해 보고 결과를 출력한다(키는 남겨 둠 — 확인 뒤 지운다).
        if let account = UserDefaults.standard.string(forKey: "debugCryptoCheck") {
            let crypto = EppCrypto(account: account)
            let ok = (try? crypto.decrypt(crypto.encrypt(Data("check".utf8)))) == Data("check".utf8)
            print("CRYPTO \(ok ? "OK" : "FAIL") certificateSigned=\(EppCrypto.isCertificateSigned)")
            NSApp.terminate(nil)
        }
        // -debugCycleModules "keepy,clocky" -debugCycleTimes 20 : 켜고 끄기를 반복해 남는 것이 없는지 보고 끝낸다.
        if let list = UserDefaults.standard.string(forKey: "debugCycleModules") {
            let ids = list.split(separator: ",").map(String.init)
            let times = max(1, UserDefaults.standard.integer(forKey: "debugCycleTimes"))
            Task { @MainActor in
                let problems = await manager.debugCycle(ids: ids, times: times)
                let report = problems.isEmpty ? "CYCLE OK \(ids) × \(times)" : "CYCLE FAIL\n" + problems.joined(separator: "\n")
                print(report)
                try? report.write(toFile: NSTemporaryDirectory() + "epp-cycle.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        #endif

        // 처음 켤 때는 켠 기능이 없으니 설정 창을 열어 기능을 고르게 한다.
        if manager.soloID == nil && !hasLaunchedBefore {
            hasLaunchedBefore = true
            showSettings(page: nil)
        }
    }

    /// 이미 켜져 있는 Epp를 Finder나 Spotlight로 다시 열면 설정 창을 띄운다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings(page: nil) }
        return true
    }

    /// 저장하지 못한 내용이 있는 기능은 끄기 전에 묻는다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for type in manager.enabledTypes {
            if let module = manager.module(id: type.info.id), !module.shouldQuit() { return .terminateCancel }
        }
        return .terminateNow
    }

    // MARK: 알림

    /// 알림을 누르면 보낸 기능에게 넘긴다.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let moduleID = response.notification.request.content.userInfo[EppNotifications.moduleKey] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let moduleID, let module = self.manager.module(id: moduleID) else { return }
                module.handleNotification(identifier: identifier)
            }
        }
        completionHandler()
    }

    /// Epp가 앞에 있어도 배너를 띄우고 알림 목록에 남긴다.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopAll()
    }

    /// epp://<기능 id>/<명령> — 예: epp://keepy/show
    /// 웹페이지나 다른 앱도 이 주소를 열 수 있다. 그래서 기능은 창 열기처럼 해가 없는 명령만 받고(모르는 명령은 무시),
    /// 여기서는 짧은 시간에 몰려오는 주소를 막는다(스티커를 수백 개 만들게 하는 등).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "epp" {
            guard urlGate.allow() else {
                EppLog.write("Epp", "주소가 너무 많이 와서 무시: \(url.host ?? "")\(url.path)")
                continue
            }
            guard let id = url.host?.lowercased() else { continue }
            if let module = manager.module(id: id) {
                module.handle(url: url)
            } else if ModuleList.type(id: id) != nil {
                // 꺼진 기능이면 켤 수 있게 설정을 연다.
                showSettings(page: id)
            }
        }
    }

    /// Dock 아이콘을 오른쪽 클릭하면 메뉴바 메뉴와 같은 기능 메뉴를 보여 준다(설정·종료는 macOS가 따로 붙인다).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        // 마지막 구분선과 "Epp 종료"는 Dock 메뉴의 기본 "종료"와 겹치므로 뺀다.
        while let last = menu.items.last, last.isSeparatorItem || last.action == #selector(NSApplication.terminate(_:)) {
            menu.removeItem(last)
        }
        return menu
    }

    private var urlGate = RateGate(limit: 5, per: 10)

    /// 기능이 Epp 아이콘 옆에 붙인 글. 기능 목록 순서로 이어 붙인다.
    private var statusTexts: [String: String] = [:]

    private func setStatusText(_ text: String?, for id: String) {
        statusTexts[id] = text?.isEmpty == false ? text : nil
        let joined = ModuleList.all.compactMap { statusTexts[$0.info.id] }.joined(separator: "  ")
        guard let button = statusItem?.button, button.title != (joined.isEmpty ? "" : " " + joined) else { return }
        button.imagePosition = joined.isEmpty ? .imageOnly : .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = joined.isEmpty ? "" : " " + joined
        statusItem.length = joined.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    @objc func openSettings() { showSettings(page: nil) }

    @objc private func openQuickSearch() {
        // 메뉴가 닫힌 뒤에 패널이 키 입력을 받게 한 박자 늦춘다.
        DispatchQueue.main.async { self.quickSearch.show() }
    }

    func showSettings(page: String?) { settingsWindow.show(page: page) }

    // MARK: 메뉴바 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let soloID = manager.soloID, let module = manager.module(id: soloID) {
            // 단독 실행: 그 기능의 메뉴를 바로 보여 준다(원래 단독 앱과 같은 모양).
            module.fillMenu(menu)
            menu.addItem(.separator())
            menu.addItem(withTitle: L("설정…"), action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(AppUpdater.shared.makeMenuItem())
            if module.makeGettingStarted() != nil {
                let guide = menu.addItem(withTitle: L("시작 안내"), action: #selector(openGettingStarted(_:)), keyEquivalent: "")
                guide.target = self
                guide.representedObject = soloID
            }
            menu.addItem(.separator())
            let name = type(of: module).info.name
            menu.addItem(withTitle: L("%@ 종료", name), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            return
        }

        let types = manager.enabledTypes
        if types.isEmpty {
            let empty = menu.addItem(withTitle: L("켠 기능이 없어요"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(withTitle: L("기능 켜기…"), action: #selector(openSettings), keyEquivalent: "").target = self
        }
        if !types.isEmpty {
            let search = menu.addItem(withTitle: L("빠른 검색…"), action: #selector(openQuickSearch), keyEquivalent: "")
            search.target = self
            search.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            if let combo = QuickSearch.combo {
                search.keyEquivalent = combo.menuKey
                search.keyEquivalentModifierMask = combo.menuModifiers
            }
            menu.addItem(.separator())
        }
        for type in types {
            guard let module = manager.module(id: type.info.id) else { continue }
            let item = menu.addItem(withTitle: type.info.name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: type.info.symbol, accessibilityDescription: nil)
            let sub = NSMenu(title: type.info.name)
            module.fillMenu(sub)
            sub.addItem(.separator())
            if module.makeGettingStarted() != nil {
                let guide = sub.addItem(withTitle: L("시작 안내"), action: #selector(openGettingStarted(_:)), keyEquivalent: "")
                guide.target = self
                guide.representedObject = type.info.id
            }
            let settings = sub.addItem(withTitle: L("%@ 설정…", type.info.name), action: #selector(openModuleSettings(_:)), keyEquivalent: "")
            settings.target = self
            settings.representedObject = type.info.id
            item.submenu = sub
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("설정…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(AppUpdater.shared.makeMenuItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Epp 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// 시작하기 상자를 다시 보이게 하고 그 기능의 설정(일반 탭)을 연다.
    @objc private func openGettingStarted(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(false, forKey: EppSettingsKeys.gettingStartedHidden(id))
        UserDefaults.standard.set("general", forKey: EppSettingsKeys.tab(id))
        showSettings(page: id)
    }

    @objc private func openModuleSettings(_ sender: NSMenuItem) {
        showSettings(page: sender.representedObject as? String)
    }

    // MARK: 앱 메뉴 (설정 창에서 ⌘W, 복사·붙이기가 되도록 + 기능이 더한 메뉴)

    /// 본체 메뉴(Epp · 편집 · 윈도우)에 켠 기능의 메뉴를 자리별로 합친다: Epp · 파일 · 편집 · 서식 · 윈도우.
    /// 같은 자리에 있으면 그 아래에 이어 붙이고, 같은 동작·같은 키의 항목은 한 번만 넣는다.
    func rebuildMainMenu() {
        let base = makeMainMenu()
        var slots: [EppMainMenu.Slot: NSMenu] = [
            .edit: base.items[1].submenu!,
            .window: base.items[2].submenu!,
        ]
        for type in manager.enabledTypes {
            guard let module = manager.module(id: type.info.id) else { continue }
            for extra in module.mainMenus() {
                guard let target = slots[extra.slot] else {
                    slots[extra.slot] = extra.menu
                    continue
                }
                var added = false
                for item in extra.menu.items {
                    if item.isSeparatorItem { continue }
                    let duplicate = target.items.contains {
                        $0.action == item.action && $0.keyEquivalent == item.keyEquivalent
                            && $0.keyEquivalentModifierMask == item.keyEquivalentModifierMask && $0.tag == item.tag
                    }
                    if duplicate { continue }
                    if !added { target.addItem(.separator()); added = true }
                    extra.menu.removeItem(item)
                    target.addItem(item)
                }
            }
        }
        let main = NSMenu()
        if let app = base.items.first {
            base.removeItem(app)
            main.addItem(app)
        }
        for slot in EppMainMenu.Slot.allCases {
            guard let menu = slots[slot] else { continue }
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            menu.supermenu?.setSubmenu(nil, for: menu.supermenu!.items.first { $0.submenu === menu }!)
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = main.addItem(withTitle: "Epp", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Epp")
        appMenu.addItem(withTitle: L("설정…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Epp 숨기기"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L("기타 숨기기"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("모두 보기"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Epp 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = main.addItem(withTitle: L("편집"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: L("편집"))
        edit.addItem(withTitle: L("실행 취소"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("실행 복귀"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("오려두기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("복사"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("붙이기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("전체 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = main.addItem(withTitle: L("윈도우"), action: nil, keyEquivalent: "")
        let window = NSMenu(title: L("윈도우"))
        window.addItem(withTitle: L("창 닫기"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        return main
    }
}

/// 정한 시간 안에 정한 횟수까지만 통과시킨다(epp:// 주소 몰림 막기).
struct RateGate {
    let limit: Int
    let per: TimeInterval
    private var times: [Date] = []

    init(limit: Int, per: TimeInterval) {
        self.limit = limit
        self.per = per
    }

    mutating func allow(now: Date = Date()) -> Bool {
        times.removeAll { now.timeIntervalSince($0) >= per }
        guard times.count < limit else { return false }
        times.append(now)
        return true
    }
}
