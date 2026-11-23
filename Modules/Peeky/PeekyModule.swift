import AppKit
import Carbon
import Combine
import EppKit
import SwiftUI

/// 메뉴바(옛 Peeky): 노치에 가려진 메뉴바 아이콘을 바에 모아 보여 주고, 고른 아이콘을 메뉴바에서 숨긴다.
/// 원래 단독 앱(eddieee-git/mac-app-peeky)의 AppDelegate를 Epp 기능 약속에 맞게 옮긴 것.
///
/// Peeky는 그룹마다 자기 메뉴바 아이콘을, 숨기기를 켜면 ‹ › 버튼과 구분선을 따로 만든다(그게 Peeky가 하는 일이라서).
/// Epp 메뉴의 "Peeky ▸"에는 같은 동작을 모아 둔다.
@MainActor
public final class PeekyModule: EppModule {
    public static let info = EppModuleInfo(
        id: "peeky", storageName: "Peeky", nameKo: "메뉴바", nameEn: "Menu Bar", symbol: "menubar.rectangle",
        summaryKo: "노치에 가려진 메뉴바 아이콘 꺼내 보기",
        summaryEn: "Menu bar icons hidden behind the notch"
    )

    private let context: EppContext
    private let prefs: Preferences
    /// One menu bar icon per group.
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var taskbar: TaskbarController!
    private let hider = MenuBarHider()
    private var hotKeys: [HotKey] = []
    private var refreshWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var isArranging = false
    private var arrangeRetries = 0
    /// 기능을 끈 뒤에는 늦게 도착한 일(정리 다시 하기 등)을 하지 않는다.
    private var isRunning = false
    /// 지금까지 본 아이콘. 새 아이콘이 생기면 자리를 정리한다.
    private var seenItemIDs: Set<String>?

    private static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    public required init(context: EppContext) {
        self.context = context
        // 여러 곳이 Preferences.shared와 PeekyStorage를 쓰므로 Epp가 준 저장소로 먼저 바꿔 둔다.
        PeekyStorage.defaults = context.defaults
        prefs = Preferences(defaults: context.defaults)
        Preferences.shared = prefs
    }

    public func start() {
        isRunning = true
        taskbar = TaskbarController(hider: hider, openSettings: { [weak self] in self?.showSettings() })

        // @Published emits the new value before it is stored, so pass it along explicitly.
        prefs.$groups
            .sink { [weak self] groups in self?.syncGroups(groups) }
            .store(in: &cancellables)
        prefs.$hotKeyModifiers
            .dropFirst()
            .sink { [weak self] _ in
                // 값이 저장된 뒤에 단축키와 아이콘 설명을 함께 다시 만든다.
                DispatchQueue.main.async { if let self, self.isRunning { self.syncGroups(self.prefs.groups) } }
            }
            .store(in: &cancellables)
        // 접을 때 Peeky 그룹 아이콘과 Epp 아이콘은 밀려나면 안 된다.
        hider.protectedItems = { [weak self] in
            guard let self else { return [] }
            return Array(self.statusItems.values) + self.context.hostStatusItems()
        }
        StatusIconCheck.groupItems = { [weak self] in
            guard let self else { return [] }
            return self.prefs.groups.compactMap { group in self.statusItems[group.id].map { (group.name, $0) } }
        }
        StatusIconCheck.resetPositions = { [weak self] in self?.resetIconPositions() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isRunning else { return }
            ItemStore.log("status icons hidden=\(StatusIconCheck.hiddenGroupNames())")
            // `open -a Epp --args --reset-icons`: 아이콘을 못 찾을 때 셸에서 자리를 되돌린다.
            if CommandLine.arguments.contains("--reset-icons") { StatusIconCheck.resetPositions() }
            if CommandLine.arguments.contains("--arrange") { StatusIconCheck.arrange() }
        }
        hider.onBlocked = { [weak self] in self?.showHiderBlocked() }
        hider.onRightClick = { [weak self] item in self?.showMenu(for: nil, on: item) }
        StatusIconCheck.arrange = { [weak self] in self?.arrangeMenuBar(collapseAfter: true) }
        StatusIconCheck.bringToFront = { [weak self] id in self?.bringToFront(id) }
        // 시작할 때는 바로 접는다. 설정에서 새로 켜면 고른 대로 아이콘을 옮긴 뒤 접는다.
        hider.setEnabled(prefs.hideInMenuBar)
        prefs.$hideInMenuBar
            .dropFirst()
            .sink { [weak self] enabled in
                self?.hider.setEnabled(enabled, collapseNow: false)
                if enabled { self?.arrangeMenuBar(collapseAfter: true) }
            }
            .store(in: &cancellables)
        // 아이콘마다 「보이기 / 숨기기」를 바꾸면 잠시 뒤 한 번에 다시 정리한다.
        Publishers.Merge(prefs.$assignments.map { _ in () }, prefs.$excludedIDs.map { _ in () })
            .dropFirst(2)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.prefs.hideInMenuBar else { return }
                self.arrangeMenuBar(collapseAfter: false)
            }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appsChanged() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appsChanged() }
        })

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        ItemStore.log("launch \(Bundle.main.bundlePath) version=\(version) axTrusted=\(AX.isTrusted) preflight=\(CGPreflightScreenCaptureAccess())")
        ItemStore.shared.checkScreenCapture()
        // 권한이 없으면 시작하기 상자와 함께 설정을 연다(처음 켤 때는 Epp가 이미 연다).
        if !AX.isTrusted {
            prefs.hasLaunchedBefore = true
            context.showGettingStarted()
            AX.requestTrust()
        }
        ItemStore.shared.refresh(full: true) { [weak self] in self?.noteNewItems() }
    }

    public func stop() {
        isRunning = false
        cancellables.removeAll()
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers.removeAll()
        refreshWork?.cancel()
        hotKeys.removeAll()
        taskbar?.hide()
        // 접힌 구분선이 남아 다른 항목을 가리지 않게 펼친 뒤 지운다.
        hider.expand()
        hider.setEnabled(false)
        for item in statusItems.values { NSStatusBar.system.removeStatusItem(item) }
        statusItems.removeAll()
        StatusIconCheck.groupItems = { [] }
        StatusIconCheck.resetPositions = {}
        StatusIconCheck.arrange = {}
        StatusIconCheck.bringToFront = { _ in }
    }

    public func settingsTabs() -> [EppSettingsTab] { PeekySettings.tabs() }

    public func makeGettingStarted() -> AnyView? { AnyView(PeekyGettingStarted(openPermissions: context.openPermissions)) }

    /// epp://peeky/open — 첫 그룹 바를 연다. epp://peeky/arrange — 다시 정리.
    public func handle(url: URL) {
        switch url.pathComponents.dropFirst().first ?? "open" {
        case "arrange": arrangeMenuBar(collapseAfter: true)
        default: if let first = prefs.groups.first { toggleBar(group: first.id) }
        }
    }

    public static func runSelfTest() -> Bool { SelfTest.run() }

    public func globalShortcuts() -> [EppShortcutInfo] {
        let modifiers = prefs.hotKeyModifiers
        guard modifiers != .off else { return [] }
        var list: [EppShortcutInfo] = []
        if !prefs.groups.isEmpty {
            list.append(.init(title: L("첫 그룹 열기"), keys: "\(modifiers.symbol)B"))
        }
        for (index, group) in prefs.groups.prefix(Self.numberKeys.count).enumerated() {
            list.append(.init(title: L("%@ 열기", group.name), keys: "\(modifiers.symbol)\(index + 1)"))
        }
        return list
    }

    public static let permissionNeeds = [
        EppPermissionNeed(.accessibility, required: true,
                          reasonKo: "다른 앱의 메뉴바 아이콘을 찾고 누르기",
                          reasonEn: "Find and click other apps' menu bar icons"),
        EppPermissionNeed(.screenRecording, required: false,
                          reasonKo: "아이콘 바에 실제 아이콘 모양 보여 주기 (없으면 앱 아이콘)",
                          reasonEn: "Show real icon images in the icon bar (app icons without it)"),
    ]

    private func showSettings() { context.openSettings() }

    // MARK: Epp 메뉴의 "Peeky ▸"

    public func fillMenu(_ menu: NSMenu) {
        for (index, group) in prefs.groups.enumerated() {
            let title = prefs.groups.count == 1 ? L("바 열기") : L("%@ 열기", group.name)
            let open = menu.addItem(withTitle: title, action: #selector(menuOpenGroup(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = group.id
            if prefs.hotKeyModifiers != .off, index < Self.numberKeys.count {
                open.keyEquivalent = "\(index + 1)"
                open.keyEquivalentModifierMask = KeyCombo(keyCode: 0, modifiers: prefs.hotKeyModifiers.carbonFlags, key: "").menuModifiers
            }
        }
        if hider.isEnabled {
            menu.addItem(.separator())
            let title = hider.isCollapsed ? L("숨긴 아이콘 보이기") : L("아이콘 다시 숨기기")
            menu.addItem(withTitle: title, action: #selector(menuToggleHidden), keyEquivalent: "").target = self
            menu.addItem(withTitle: L("다시 정리"), action: #selector(menuArrange), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("바 아이콘을 오른쪽 끝으로 옮기기"), action: #selector(menuResetIcons), keyEquivalent: "").target = self
    }

    @objc private func menuArrange() { arrangeMenuBar(collapseAfter: true) }
    @objc private func menuResetIcons() { resetIconPositions() }

    // MARK: Menu bar hiding

    /// 「숨기기」로 고른 아이콘은 › 왼쪽, 「보이기」는 오른쪽에 오도록 하나씩 옮긴다.
    /// 옮길 때마다 자리가 바뀌므로 매번 다시 읽는다. 마우스를 직접 움직이므로 안전하게:
    /// - 메뉴바가 안 보이면(전체 화면 등) 하지 않는다. 클릭이 앱 화면에 들어갈 수 있다.
    /// - 사용자가 마우스를 누르거나 움직이면 멈추고 잠시 뒤 다시 한다.
    /// - 옮긴 아이콘이 메뉴바에서 사라졌으면 멈추고 알린다.
    /// - 노치 뒤라 잡을 수 없거나 옮겨지지 않은 아이콘은 「옮기지 못함」으로 표시한다.
    private func arrangeMenuBar(collapseAfter: Bool) {
        guard isRunning, hider.isEnabled, AX.isTrusted, !isArranging else { return }
        guard NSEvent.pressedMouseButtons == 0, hider.menuBarIsVisible else {
            retryArrangeLater(collapseAfter: collapseAfter)
            return
        }
        isArranging = true
        let wasCollapsed = hider.isCollapsed
        hider.expand()
        var tried = Set<String>()
        var unmovable = Set<String>()
        var moved = 0
        var pointer = NSEvent.mouseLocation
        var pending: (id: String, name: String, wasLeft: Bool)?

        func userIsBusy() -> Bool {
            let now = NSEvent.mouseLocation
            return NSEvent.pressedMouseButtons != 0 || hypot(now.x - pointer.x, now.y - pointer.y) > 3
                || !hider.menuBarIsVisible || !isRunning
        }
        func finish(interrupted: Bool) {
            isArranging = false
            ItemStore.shared.unmovableIDs = unmovable
            ItemStore.log("arrange: moved \(moved), unmovable \(unmovable.count), interrupted \(interrupted)")
            guard isRunning else { return }
            if collapseAfter || wasCollapsed { hider.collapse() }
            if interrupted { retryArrangeLater(collapseAfter: collapseAfter) } else { arrangeRetries = 0 }
        }
        var firstScan = true
        func step(recheckedMissing: Bool = false) {
            // 처음 한 번만 모든 앱을 훑고, 그다음부터는 아이콘이 있는 앱만 다시 읽는다(빠르다).
            let full = firstScan
            firstScan = false
            ItemStore.shared.refresh(full: full) { [self] in
                if userIsBusy() { finish(interrupted: true); return }
                let items = ItemStore.shared.items
                guard let divider = hider.dividerFrame, let toggle = hider.toggleFrame else { finish(interrupted: false); return }
                if let last = pending {
                    guard let item = items.first(where: { $0.id == last.id }) else {
                        // 한 번 못 읽었을 수도 있으니 잠깐 뒤 다시 본다.
                        if !recheckedMissing {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                MainActor.assumeIsolated { step(recheckedMissing: true) }
                            }
                            return
                        }
                        finish(interrupted: false)
                        showIconLost(name: last.name)
                        return
                    }
                    pending = nil
                    if let frame = item.frame, (frame.midX < divider.midX) == last.wasLeft { unmovable.insert(item.id) }
                }
                guard tried.count < 40 else { finish(interrupted: false); return }
                let plan = nextMove(in: items, divider: divider, toggle: toggle, skipping: tried)
                unmovable.formUnion(plan.blocked)
                guard let (item, move) = plan.move else { finish(interrupted: false); return }
                tried.insert(item.id)
                moved += 1
                pending = (item.id, item.displayName, move.from.midX < divider.midX)
                ItemMover.perform([move]) {
                    MainActor.assumeIsolated { pointer = NSEvent.mouseLocation }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { step() } }
                }
            }
        }
        // 펼친 뒤 메뉴바가 자리를 잡을 시간을 준다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { step() } }
    }

    /// 「보이기」 아이콘 하나를 시계·제어 센터 바로 왼쪽으로 옮긴다. macOS는 자리가 모자라면 왼쪽부터 숨기므로
    /// 오른쪽에 있을수록 오래 보인다.
    private func bringToFront(_ id: String) {
        guard AX.isTrusted, !isArranging, NSEvent.pressedMouseButtons == 0 else { return }
        ItemStore.shared.refresh(full: true) { [self] in
            let items = ItemStore.shared.items
            guard let item = items.first(where: { $0.id == id }), let frame = item.frame,
                  !NotchGeometry.isHidden(frame),
                  let anchor = items.filter(\.isFixed).compactMap(\.frame).min(by: { $0.minX < $1.minX }),
                  frame.maxX < anchor.minX - 2 else {
                ItemStore.log("bring-to-front: skipped \(id)")
                return
            }
            if prefs.hideInMenuBar, !hider.menuBarIsVisible { return }
            ItemMover.perform([.init(from: frame, toX: anchor.minX - 3)]) {
                MainActor.assumeIsolated { ItemStore.shared.refresh(full: false) }
            }
        }
    }

    /// 사용자가 마우스를 쓰고 있었거나 메뉴바가 가려져 있었으면 조금 뒤 다시 한다(몇 번까지만).
    private func retryArrangeLater(collapseAfter: Bool) {
        guard arrangeRetries < 6 else { arrangeRetries = 0; return }
        arrangeRetries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.prefs.hideInMenuBar else { return }
                self.arrangeMenuBar(collapseAfter: collapseAfter)
            }
        }
    }

    /// 옮겨야 할 다음 아이콘. 옮겨야 하지만 노치 뒤라 잡을 수 없는 아이콘은 `blocked`로 돌려준다.
    private func nextMove(in items: [MenuBarItem], divider: NSRect, toggle: NSRect, skipping: Set<String>)
        -> (move: (MenuBarItem, ItemMover.Move)?, blocked: Set<String>) {
        var blocked = Set<String>()
        // 화면이 여러 개면 메뉴바도 여럿이다. Peeky의 ‹ › 버튼이 있는 화면의 아이콘만 옮긴다.
        let menuScreen = NSScreen.screens.first { $0.frame.minX <= toggle.midX && toggle.midX < $0.frame.maxX }
        for item in items where !skipping.contains(item.id) && !item.isFixed {
            guard let frame = item.frame, frame.width > 1 else { continue }
            if let menuScreen, frame.midX >= menuScreen.frame.minX, frame.midX < menuScreen.frame.maxX {
                // 같은 화면. 아래에서 계속.
            } else if !NotchGeometry.isOffScreen(frame) {
                continue   // 다른 화면의 메뉴바에 있는 아이콘
            }
            let wantsHidden = prefs.group(for: item.id) != nil
            let isLeft = frame.midX < divider.midX
            guard wantsHidden != isLeft else { continue }
            if NotchGeometry.isHidden(frame) { blocked.insert(item.id); continue }
            let target = wantsHidden ? divider.minX - 3 : toggle.maxX + 3
            return ((item, .init(from: frame, toX: target)), blocked)
        }
        return (nil, blocked)
    }

    private func showIconLost(name: String) {
        let alert = NSAlert()
        alert.messageText = L("%@ 아이콘이 메뉴바에서 사라졌어요", name)
        alert.informativeText = L("옮기는 중에 메뉴바 밖에 놓였을 수 있어요. 그 앱을 종료했다가 다시 열면 돌아와요. 정리는 멈췄어요.")
        NSApp.activate()
        alert.runModal()
    }

    private func showHiderBlocked() {
        let alert = NSAlert()
        alert.messageText = L("바 아이콘이나 Epp 아이콘이 › 버튼 왼쪽에 있어요")
        alert.informativeText = L("이대로 숨기면 그 아이콘도 사라져서 펼쳐 두었어요. 바 아이콘을 오른쪽 끝으로 옮긴 뒤 › 버튼을 다시 눌러 주세요. Epp 아이콘은 ⌘를 누른 채 › 오른쪽으로 끌어 주세요.")
        alert.addButton(withTitle: L("바 아이콘을 오른쪽 끝으로 옮기기"))
        alert.addButton(withTitle: L("닫기"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { resetIconPositions() }
    }

    // MARK: Groups → status items & hot keys

    /// 아이콘을 지웠다가 처음 자리로 다시 만든다. 노치 뒤나 구분선 왼쪽에 들어가 못 찾을 때 쓴다.
    private func resetIconPositions() {
        guard isRunning else { return }
        let hiding = prefs.hideInMenuBar
        hider.setEnabled(false)
        for item in statusItems.values { NSStatusBar.system.removeStatusItem(item) }
        statusItems.removeAll()
        DispatchQueue.main.async { [self] in
            guard isRunning else { return }
            for (index, group) in prefs.groups.enumerated() {
                StatusItemPlacement.prepare(autosaveName: "PeekyGroup-\(group.id.uuidString)",
                                            position: StatusItemPlacement.groupPosition(index: index), force: true)
            }
            StatusItemPlacement.prepare(autosaveName: MenuBarHider.toggleAutosaveName,
                                        position: StatusItemPlacement.togglePosition, force: true)
            StatusItemPlacement.prepare(autosaveName: MenuBarHider.autosaveName,
                                        position: StatusItemPlacement.dividerPosition, force: true)
            syncGroups(prefs.groups)
            if hiding { hider.setEnabled(true, collapseNow: false) }
            ItemStore.log("status icons reset, hidden=\(StatusIconCheck.hiddenGroupNames())")
        }
    }

    private func syncGroups(_ groups: [ItemGroup]) {
        guard isRunning else { return }
        let ids = Set(groups.map(\.id))
        for (id, item) in statusItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems[id] = nil
            if taskbar.groupID == id { taskbar.hide() }
        }

        for (index, group) in groups.enumerated() {
            let item = statusItems[group.id] ?? {
                let name = "PeekyGroup-\(group.id.uuidString)"
                StatusItemPlacement.prepare(autosaveName: name, position: StatusItemPlacement.groupPosition(index: index))
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.autosaveName = name
                item.button?.target = self
                item.button?.action = #selector(statusItemClicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                item.button?.identifier = NSUserInterfaceItemIdentifier(group.id.uuidString)
                statusItems[group.id] = item
                return item
            }()
            item.button?.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)
                ?? NSImage(systemSymbolName: "ellipsis.rectangle", accessibilityDescription: group.name)
            item.button?.toolTip = "\(Self.info.name) – \(group.name) \(shortcutText(index: index))"
        }
        registerHotKeys(groups: groups, modifiers: prefs.hotKeyModifiers)
    }

    func shortcutText(index: Int) -> String {
        let modifiers = prefs.hotKeyModifiers
        guard modifiers != .off, index < Self.numberKeys.count else { return "" }
        return "\(modifiers.symbol)\(index + 1)"
    }

    /// <보조 키>+B는 첫 그룹, <보조 키>+1…9는 각 그룹을 연다.
    private func registerHotKeys(groups: [ItemGroup], modifiers: HotKeyModifiers) {
        hotKeys.removeAll()
        guard modifiers != .off else { return }
        if let first = groups.first {
            addHotKey(kVK_ANSI_B, modifiers: modifiers, group: first.id)
        }
        for (index, group) in groups.prefix(Self.numberKeys.count).enumerated() {
            addHotKey(Self.numberKeys[index], modifiers: modifiers, group: group.id)
        }
    }

    private func addHotKey(_ key: Int, modifiers: HotKeyModifiers, group: UUID) {
        if let hotKey = HotKey(keyCode: UInt32(key), modifiers: modifiers.carbonFlags, action: { [weak self] in
            self?.toggleBar(group: group)
        }) {
            hotKeys.append(hotKey)
        } else {
            ItemStore.log("hotkey \(modifiers.symbol)\(key) could not be registered (already in use?)")
        }
    }

    private func appsChanged() {
        guard isRunning else { return }
        // Apps add their status items a moment after launching; debounce and rescan everything.
        ItemStore.shared.invalidate()
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            ItemStore.shared.refresh(full: true) {
                MainActor.assumeIsolated { self?.noteNewItems() }
            }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 새 앱의 아이콘은 macOS가 왼쪽 끝(숨기는 쪽)에 놓는다. 새 아이콘은 「보이기」가 기본이라 자리를 맞춘다.
    private func noteNewItems() {
        guard isRunning else { return }
        let ids = Set(ItemStore.shared.items.map(\.id))
        defer { seenItemIDs = (seenItemIDs ?? []).union(ids) }
        guard let seen = seenItemIDs, !ids.subtracting(seen).isEmpty, prefs.hideInMenuBar else { return }
        arrangeMenuBar(collapseAfter: false)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let group = UUID(uuidString: raw) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(for: group, on: statusItems[group])
        } else {
            toggleBar(group: group)
        }
    }

    private func toggleBar(group: UUID) {
        taskbar.toggle(group: group, anchor: statusItems[group]?.button?.window?.frame)
    }

    /// 그룹 아이콘이나 ‹ › 버튼·구분선을 오른쪽 클릭했을 때의 메뉴. 꼭 필요한 것만 둔다:
    /// 바 열기, (숨기기를 켰을 때) 펼치기/숨기기, 설정. (종료는 Epp 메뉴에 있다)
    private func showMenu(for group: UUID?, on statusItem: NSStatusItem?) {
        guard let statusItem else { return }
        taskbar.hide()
        let menu = NSMenu()
        let shown = prefs.groups.filter { group == nil || $0.id == group }
        for g in shown {
            let title = prefs.groups.count == 1 ? L("바 열기") : L("%@ 열기", g.name)
            let open = menu.addItem(withTitle: title, action: #selector(menuOpenGroup(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = g.id
        }
        if hider.isEnabled {
            let title = hider.isCollapsed ? L("숨긴 아이콘 보이기") : L("아이콘 다시 숨기기")
            menu.addItem(withTitle: title, action: #selector(menuToggleHidden), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("메뉴바 설정…"), action: #selector(menuSettings), keyEquivalent: ",").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenGroup(_ sender: NSMenuItem) {
        if let group = sender.representedObject as? UUID { toggleBar(group: group) }
    }

    @objc private func menuToggleHidden() {
        hider.isCollapsed ? hider.expand() : hider.collapse()
    }

    @objc private func menuSettings() { showSettings() }
}
