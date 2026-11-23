import AppKit
import Combine
import EppKit
import SwiftUI

/// 클립보드(옛 Keepy): 복사한 내용을 모아 두었다가 다시 붙여 넣는 클립보드 기록.
/// 원래 단독 앱(eddieee-git/mac-app-keepy)의 AppDelegate를 Epp 기능 약속에 맞게 옮긴 것.
@MainActor
public final class KeepyModule: EppModule {
    public static let info = EppModuleInfo(
        id: "keepy", storageName: "Keepy", nameKo: "클립보드", nameEn: "Clipboard", symbol: "doc.on.clipboard",
        summaryKo: "복사한 내용을 모아 두고 다시 붙여 넣는 클립보드 기록",
        summaryEn: "Clipboard history to paste again"
    )

    let context: EppContext
    let settings: AppSettings
    let store: HistoryStore
    private lazy var monitor = ClipboardMonitor(settings: settings) { [weak self] content, app in
        self?.store.add(content, source: app)
    }
    private lazy var panel = PanelController(store: store) { [weak self] item, plainText in
        self?.paste(item, plainText: plainText)
    }
    private var hotKey: HotKey?
    /// 오래된 기록을 지우려고 한 시간마다 본다.
    private var trimTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    public required init(context: EppContext) {
        self.context = context
        // 기능 안 여러 곳이 AppSettings.shared를 쓰므로 Epp가 준 저장소로 먼저 바꿔 둔다.
        let settings = AppSettings(defaults: context.defaults)
        self.settings = settings
        AppSettings.shared = settings
        store = HistoryStore(directory: context.dataDirectory,
                             limit: { settings.historyLimit },
                             maxAgeDays: { settings.historyMaxAgeDays })
    }

    public func start() {
        // @Published는 값이 저장되기 전에 알리므로, 다음 차례에 다시 등록한다.
        settings.$hotKey
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotKey() } }
            .store(in: &cancellables)
        settings.$historyLimit.map { _ in () }
            .merge(with: settings.$historyMaxAgeDays.map { _ in () })
            .dropFirst(2)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.store.trim() } }
            .store(in: &cancellables)

        monitor.start()
        applyHotKey()
        panel.viewModel.makeSticky = { [weak self] item in
            guard let self else { return false }
            self.panel.hide()
            return self.context.send(.makeSticky(text: item.text))
        }
        trimTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.trim() }
        }
    }

    public func stop() {
        cancellables.removeAll()
        trimTimer?.invalidate()
        trimTimer = nil
        hotKey = nil
        monitor.stop()
        panel.hide()
        store.commitDeletion()
        store.saveNow()
    }

    /// epp://keepy/show — 다른 도구(단축어 등)에서 기록 창을 연다.
    public func handle(url: URL) {
        let command = url.pathComponents.dropFirst().first ?? "show"
        if command == "show" { showPanel() } else { EppLog.write("클립보드", "모르는 주소 명령 무시: \(url.path)") }
    }

    /// 빠른 검색: 글과 파일 경로에서 찾는다. 고르면 앞의 앱에 붙여 넣는다(설정에 따라 복사만).
    public func search(_ query: EppSearchQuery) -> [EppSearchResult] {
        store.items.lazy.filter { $0.kind != .image && query.matches($0.text) }.prefix(30).map { item in
            EppSearchResult(id: "keepy." + item.id.uuidString, title: item.title,
                            detail: [query.snippet(item.text), item.sourceAppName].compactMap { $0 }.joined(separator: " · "),
                            symbol: item.kind == .file ? "doc" : (item.pinned ? "pin" : "doc.on.clipboard"),
                            date: item.lastUsedAt) { [weak self] in self?.paste(item, plainText: false) }
        }
    }

    public func settingsTabs() -> [EppSettingsTab] {
        KeepySettings.tabs(settings: settings, store: store)
    }

    public func makeGettingStarted() -> AnyView? {
        AnyView(KeepyGettingStarted(settings: settings, store: store, openPermissions: context.openPermissions))
    }

    public static func runSelfTest() -> Bool { SelfTest.run() }

    public func globalShortcuts() -> [EppShortcutInfo] {
        settings.hotKey.map { [EppShortcutInfo(title: L("클립보드 기록 열기"), keys: $0.displayText)] } ?? []
    }

    public static let permissionNeeds = [
        EppPermissionNeed(.accessibility, required: false,
                          reasonKo: "고른 항목을 앞에 있던 앱에 바로 붙여 넣기 (없으면 복사만)",
                          reasonEn: "Paste the picked item into the app you were using (copies only without it)"),
    ]

    // MARK: 동작

    func showPanel() {
        // 메뉴가 닫힌 뒤에 패널이 키 윈도우가 되도록 한 박자 늦춘다.
        DispatchQueue.main.async { self.panel.show() }
    }

    /// 항목을 클립보드에 올리고, 설정에 따라 앞에 있던 앱에 ⌘V를 보낸다.
    func paste(_ item: ClipItem, plainText: Bool) {
        let fromPanel = panel.isVisible
        panel.hide()
        Paster.write(item, store: store, plainText: plainText)
        monitor.syncChangeCount()
        store.markUsed(item.id)
        if !settings.hasPasted { settings.hasPasted = true }

        // 붙여 넣지 않고 복사만 할 때는 잘 됐는지 알 수 있게 잠깐 알린다.
        let center = fromPanel ? panel.lastCenter : NSEvent.mouseLocation
        guard settings.pasteAutomatically else {
            CopiedToast.show(at: center)
            return
        }
        if Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Paster.sendPasteKeystroke() }
        } else {
            // 권한이 없으면 복사만 하고, 설정의 시작하기 상자로 권한을 켜는 방법을 알려 준다.
            CopiedToast.show(at: center)
            context.showGettingStarted()
        }
    }

    private func applyHotKey() {
        hotKey = nil
        settings.hotKeyFailed = false
        guard let combo = settings.hotKey else { return }
        hotKey = HotKey(combo: combo) { [weak self] in self?.panel.toggle() }
        settings.hotKeyFailed = hotKey == nil
    }

    // MARK: 메뉴바 메뉴

    public func fillMenu(_ menu: NSMenu) {
        let open = menu.addItem(withTitle: L("클립보드 기록 열기"), action: #selector(menuOpenPanel), keyEquivalent: "")
        open.target = self
        if let combo = settings.hotKey {
            open.keyEquivalent = combo.menuKey
            open.keyEquivalentModifierMask = combo.menuModifiers
        }
        menu.addItem(.separator())

        let recent = store.items.prefix(10)
        if recent.isEmpty {
            let empty = menu.addItem(withTitle: L("아직 복사한 항목이 없어요"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            menu.addItem(.sectionHeader(title: L("최근 항목")))
            for item in recent {
                let entry = menu.addItem(withTitle: menuTitle(item), action: #selector(menuPasteItem(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = item.id
                entry.toolTip = item.tooltip
                if item.pinned {
                    entry.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: L("고정"))
                }
            }
        }
        menu.addItem(.separator())

        let pause = menu.addItem(withTitle: L("기록 일시 정지"), action: #selector(menuTogglePause), keyEquivalent: "")
        pause.target = self
        pause.state = settings.isPaused ? .on : .off
        let clear = menu.addItem(withTitle: L("기록 지우기…"), action: #selector(menuClearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = store.items.contains { !$0.pinned }
    }

    private func menuTitle(_ item: ClipItem) -> String {
        let title = item.kind == .image ? L("이미지 %@", item.summary) : item.title
        return title.count > 45 ? String(title.prefix(45)) + "…" : title
    }

    @objc private func menuOpenPanel() { showPanel() }

    @objc private func menuPasteItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = store.items.first(where: { $0.id == id }) else { return }
        paste(item, plainText: false)
    }

    @objc private func menuTogglePause() { settings.isPaused.toggle() }

    @objc private func menuClearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("기록을 지울까요?")
        alert.informativeText = L("고정한 항목은 남겨요. 지운 기록은 되돌릴 수 없어요.")
        alert.addButton(withTitle: L("지우기"))
        alert.addButton(withTitle: L("취소"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear(includingPinned: false)
        }
    }
}
