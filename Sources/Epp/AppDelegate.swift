import AppKit
import EppKit

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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let manager: ModuleManager
    private let settingsWindow: SettingsWindowController
    private var statusItem: NSStatusItem!

    init(manager: ModuleManager) {
        self.manager = manager
        settingsWindow = SettingsWindowController(manager: manager)
        super.init()
        manager.openSettings = { [weak self] id in self?.showSettings(page: id) }
    }

    private var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunchedBefore") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunchedBefore") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        let solo = manager.soloID.flatMap(ModuleList.type(id:))?.info
        let image = NSImage(systemSymbolName: solo?.symbol ?? "square.grid.2x2", accessibilityDescription: solo?.name ?? "Epp")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = solo.map { "\($0.name) (Epp)" } ?? "Epp"

        manager.startEnabled()

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

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopAll()
    }

    /// epp://<기능 id>/<명령> — 예: epp://keepy/show
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "epp" {
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

    @objc func openSettings() { showSettings(page: nil) }

    func showSettings(page: String?) { settingsWindow.show(page: page) }

    // MARK: 메뉴바 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let soloID = manager.soloID, let module = manager.module(id: soloID) {
            // 단독 실행: 그 기능의 메뉴를 바로 보여 준다(원래 단독 앱과 같은 모양).
            module.fillMenu(menu)
            menu.addItem(.separator())
            menu.addItem(withTitle: L("설정…"), action: #selector(openSettings), keyEquivalent: ",").target = self
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
        for type in types {
            guard let module = manager.module(id: type.info.id) else { continue }
            let item = menu.addItem(withTitle: type.info.name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: type.info.symbol, accessibilityDescription: nil)
            let sub = NSMenu(title: type.info.name)
            module.fillMenu(sub)
            sub.addItem(.separator())
            let settings = sub.addItem(withTitle: L("%@ 설정…", type.info.name), action: #selector(openModuleSettings(_:)), keyEquivalent: "")
            settings.target = self
            settings.representedObject = type.info.id
            item.submenu = sub
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("설정…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Epp 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openModuleSettings(_ sender: NSMenuItem) {
        showSettings(page: sender.representedObject as? String)
    }

    // MARK: 앱 메뉴 (설정 창에서 ⌘W, 복사·붙이기가 되도록)

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
