import AppKit
import Carbon
import EppKit
import SwiftUI

/// Epp 빠른 검색: 단축키 하나로 켠 기능의 내용(클립보드 기록, 스티커, 캡처 속 글자, 타이머·알람)을 한 번에 찾는다.
/// 창은 앞의 앱을 그대로 둔 채 뜨는 패널이라, 클립보드 항목을 고르면 앞의 앱에 바로 붙여 넣을 수 있다.
@MainActor
final class QuickSearch: NSObject, NSWindowDelegate {
    static let hotKeyKey = "quickSearchHotKey"
    /// 설정에서 단축키를 바꾸면 보낸다(본체가 다시 등록한다).
    static let hotKeyChanged = Notification.Name("EppQuickSearchHotKeyChanged")
    static let defaultCombo = KeyCombo(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(controlKey | optionKey), key: "E")

    /// 저장한 단축키. 저장한 값이 빈 데이터면 사용자가 끈 것.
    static var combo: KeyCombo? {
        get {
            guard let data = UserDefaults.standard.data(forKey: hotKeyKey) else { return defaultCombo }
            return data.isEmpty ? nil : (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? defaultCombo
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: hotKeyKey)
            NotificationCenter.default.post(name: hotKeyChanged, object: nil)
        }
    }

    private let manager: ModuleManager
    private let model: QuickSearchModel
    private var panel: QuickSearchPanel?
    private var keyMonitor: Any?
    private var hotKey: HotKey?
    private(set) var hotKeyFailed = false

    init(manager: ModuleManager) {
        self.manager = manager
        model = QuickSearchModel(manager: manager)
        super.init()
    }

    func registerHotKey() {
        hotKey = nil
        hotKeyFailed = false
        guard let combo = Self.combo else { return }
        hotKey = HotKey(combo: combo) { [weak self] in self?.toggle() }
        hotKeyFailed = hotKey == nil
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show(query: String = "") {
        let panel = self.panel ?? makePanel()
        model.query = query
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: screen.midX - size.width / 2, y: screen.maxY - screen.height * 0.22 - size.height))
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
        startKeyMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        stopKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func makePanel() -> QuickSearchPanel {
        let panel = QuickSearchPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 420),
                                     styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickSearchView(model: model) { [weak self] result in self?.open(result) })
        self.panel = panel
        return panel
    }

    private func open(_ result: EppSearchResult) {
        hide()
        // 패널이 닫혀 앞의 앱이 다시 키 입력을 받은 뒤에 연다(클립보드 붙여 넣기).
        DispatchQueue.main.async { result.open() }
    }

    /// ↑↓로 고르고 ↩로 열고 esc로 닫는다. 글자 입력은 검색 칸이 받는다.
    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape: self.hide(); return nil
            case kVK_DownArrow: self.model.move(1); return nil
            case kVK_UpArrow: self.model.move(-1); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let result = self.model.selected { self.open(result) }
                return nil
            default: return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// 앞의 앱을 그대로 둔 채 키 입력을 받는 패널
final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class QuickSearchModel: ObservableObject {
    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var groups: [(info: EppModuleInfo, results: [EppSearchResult])] = []
    @Published var selection = 0
    /// 바뀌면 검색 칸에 커서를 둔다.
    @Published var focusToken = 0
    private let manager: ModuleManager

    init(manager: ModuleManager) { self.manager = manager }

    var flat: [EppSearchResult] { groups.flatMap(\.results) }
    var selected: EppSearchResult? { flat.indices.contains(selection) ? flat[selection] : nil }

    func move(_ step: Int) {
        let count = flat.count
        guard count > 0 else { return }
        selection = (selection + step + count) % count
    }

    private func refresh() {
        groups = manager.search(EppSearchQuery(query))
        selection = 0
    }
}

struct QuickSearchView: View {
    @ObservedObject var model: QuickSearchModel
    let open: (EppSearchResult) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField(L("클립보드·스티커·캡처·타이머에서 찾기"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider()
            content
        }
        .frame(width: 620, height: 420)
        .background(.regularMaterial)
        .ignoresSafeArea()
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _, _ in focused = true }
    }

    @ViewBuilder private var content: some View {
        if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            hint(L("찾을 말을 입력하세요. ↑↓로 고르고 ↩로 열어요. 클립보드 항목은 앞의 앱에 붙여 넣어요."))
        } else if model.groups.isEmpty {
            hint(L("찾는 내용이 없어요."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let ids = model.flat.map(\.id)
                        ForEach(model.groups, id: \.info.id) { group in
                            Text(group.info.name).font(.caption.bold()).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.top, 8)
                            ForEach(group.results) { result in
                                let index = ids.firstIndex(of: result.id) ?? 0
                                row(result, selected: index == model.selection)
                                    .id(result.id)
                                    .onTapGesture { open(result) }
                                    .onHover { if $0 { model.selection = index } }
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selection) { _, _ in
                    if let id = model.selected?.id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func row(_ result: EppSearchResult, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.symbol).frame(width: 20).foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).lineLimit(1)
                if let detail = result.detail {
                    Text(detail).font(.caption).lineLimit(1).foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                }
            }
            Spacer()
            if let date = result.date {
                Text(date, format: .relative(presentation: .named)).font(.caption)
                    .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? .white : .primary)
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
