import AppKit
import Carbon
import Combine
import EppKit
import SwiftUI

/// 캡처(옛 Grabby): 찍고, 그리고, 바로 붙여 넣는 화면 캡처. 원래 단독 앱(eddieee-git/mac-app-grabby)의 AppDelegate를
/// Epp 기능 약속에 맞게 옮긴 것. 메뉴는 Epp의 "캡처 ▸", 화면 기록 권한은 Epp 일반 → 권한.
@MainActor
public final class GrabbyModule: NSObject, EppModule {
    public static let info = EppModuleInfo(
        id: "grabby", storageName: "Grabby", nameKo: "캡처", nameEn: "Capture", symbol: "camera.viewfinder",
        summaryKo: "찍고, 그리고, 바로 붙여 넣는 화면 캡처",
        summaryEn: "Capture, mark up and paste"
    )

    public static let permissionNeeds = [
        EppPermissionNeed(.screenRecording, required: true,
                          reasonKo: "화면을 찍기 (화이트보드는 없어도 돼요)",
                          reasonEn: "Capture the screen (the whiteboard works without it)"),
    ]

    private let context: EppContext
    private var hotKeys: [HotKey] = []
    private var hotKeyItems: [HotKeyAction: NSMenuItem] = [:]
    private var hotKeySubscription: AnyCancellable?
    private var session: CaptureSession?
    private var library: LibraryWindowController?
    private let settings: AppSettings
    private var observers: [NSObjectProtocol] = []
    private var tidyTimer: Timer?

    public required init(context: EppContext) {
        self.context = context
        // 여러 곳이 AppSettings.shared와 GrabbyStorage를 쓰므로 Epp가 준 저장소로 먼저 바꿔 둔다.
        GrabbyStorage.defaults = context.defaults
        GrabbyStorage.folder = context.dataDirectory
        settings = AppSettings(defaults: context.defaults)
        AppSettings.shared = settings
        super.init()
    }
    /// 캡처를 시작하기 전에 앞에 있던 앱. 캡처가 끝나면 돌려줘서 바로 ⌘V로 붙여 넣을 수 있게 한다.
    private var previousApp: NSRunningApplication?

    private let lastRectKey = "lastCaptureRect"
    private let lastDisplayKey = "lastCaptureDisplay"

    public func start() {
        GrabbyTheme.apply(settings.theme)
        // 설정에서 단축키를 바꾸면 바로 다시 등록한다. 입력받는 동안에는 잠시 풀어 둔다.
        hotKeySubscription = settings.$hotKeys.combineLatest(settings.$isRecordingHotKey).sink { [weak self] combos, isRecording in
            self?.registerHotKeys(isRecording ? [:] : combos)
            self?.updateHotKeyItems(combos)
        }
        _ = CaptureStore.shared
        CaptureStore.shared.isBusy = { [weak self] in self?.session != nil || self?.isPreparingSession == true }
        // 날수로 정리하는 설정은 앱을 켜 둔 채로도 지나야 하므로 시작할 때와 한 시간마다 확인한다.
        CaptureStore.shared.tidy()
        tidyTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { _ = CaptureStore.shared.tidy() }
        }
        if settings.restorePins { PinWindow.restore() } else { PinWindow.discardSaved() }
        ScreenCapturer.warmUp()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ScreenCapturer.invalidate()
                ScreenCapturer.warmUp()
            }
        })
        // 다른 캡처 앱이 켜져 있으면 단축키가 겹칠 수 있다고 한 번 알려 준다.
        let others = HotKeyConflicts.runningCaptureApps
        let blocked = HotKeyConflicts.blockedBySystem(settings.hotKeys)
        if !blocked.isEmpty {
            Toast.show(L("%@는 macOS 스크린샷 단축키와 겹쳐요 · 설정 > 단축키에서 확인해 주세요", blocked.joined(separator: ", ")))
        } else if !others.isEmpty {
            Toast.show(L("%@이(가) 켜져 있어요 · 단축키가 겹치면 설정에서 바꿔 주세요", others.joined(separator: ", ")))
        }
    }

    private func registerHotKeys(_ combos: [String: KeyCombo]) {
        hotKeys = []
        var failed: Set<HotKeyAction> = []
        for action in HotKeyAction.allCases {
            guard let combo = combos[action.rawValue] else { continue }
            let hotKey = HotKey(combo: combo) { [weak self] in
                MainActor.assumeIsolated { self?.perform(action) }
            }
            if let hotKey { hotKeys.append(hotKey) } else { failed.insert(action) }
        }
        settings.failedHotKeys = failed
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .captureArea: captureArea()
        case .repeatLastArea: repeatLastArea()
        case .captureFullScreen: captureFullScreen()
        case .captureWindow: captureFrontWindow()
        case .captureTimer: startTimer(seconds: settings.timerSeconds)
        case .whiteboard: openWhiteboard()
        case .readCode: readCode()
        }
    }

    /// 메뉴에 지금 단축키를 보여 준다.
    private func updateHotKeyItems(_ combos: [String: KeyCombo]) {
        for (action, item) in hotKeyItems {
            let combo = combos[action.rawValue]
            item.keyEquivalent = combo?.menuKey ?? ""
            item.keyEquivalentModifierMask = combo?.menuModifiers ?? []
        }
    }

    /// 끄거나 Epp를 끝낼 때: 띄운 캡처·보관함을 저장하고, 창·단축키·타이머를 거둔다.
    public func stop() {
        PinWindow.saveAll()
        Clipboard.resolvePending()
        CaptureStore.shared.flush()
        hotKeys = []
        hotKeySubscription?.cancel()
        tidyTimer?.invalidate()
        tidyTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if timerRunning { cancelTimer() }
        library?.close()
        library = nil
        PinWindow.closeAll()
    }

    // MARK: 메뉴

    /// Epp 메뉴의 "캡처 ▸": 캡처 동작(지금 단축키 표시) → 타이머 캡처 → 탭 창.
    public func fillMenu(_ menu: NSMenu) {
        let capture = item(HotKeyAction.captureArea.title, action: #selector(captureArea))
        let repeatLast = item(HotKeyAction.repeatLastArea.title, action: #selector(repeatLastArea))
        let fullScreen = item(HotKeyAction.captureFullScreen.title, action: #selector(captureFullScreen))
        let frontWindow = item(HotKeyAction.captureWindow.title, action: #selector(captureFrontWindow))
        let whiteboard = item(HotKeyAction.whiteboard.title, action: #selector(openWhiteboard))
        let qr = item(HotKeyAction.readCode.title, action: #selector(readCode))
        hotKeyItems = [.captureArea: capture, .repeatLastArea: repeatLast, .captureFullScreen: fullScreen, .captureWindow: frontWindow, .whiteboard: whiteboard, .readCode: qr]
        [capture, repeatLast, fullScreen, frontWindow, whiteboard, qr].forEach(menu.addItem)
        let timer = NSMenuItem(title: L("타이머 캡처"), action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        let timerNow = item(L("타이머 캡처 (설정한 시간)"), action: #selector(captureWithConfiguredTimer))
        hotKeyItems[.captureTimer] = timerNow
        timerMenu.addItem(timerNow)
        timerMenu.addItem(item(L("타이머 취소"), action: #selector(cancelTimer)))
        timerMenu.addItem(.separator())
        for seconds in [3, 5, 10] {
            let entry = item(L("%ld초 뒤", seconds), action: #selector(captureWithTimer(_:)))
            entry.tag = seconds
            timerMenu.addItem(entry)
        }
        timer.submenu = timerMenu
        menu.addItem(timer)
        menu.addItem(.separator())
        menu.addItem(item(L("캡처 창 열기"), action: #selector(openLibrary)))
        menu.addItem(item(L("띄운 캡처 모두 닫기"), action: #selector(closeAllPins)))
        updateHotKeyItems(settings.hotKeys)
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// 탭 창이 앞에 있을 때 쓰는 앱 메뉴: 파일(캡처 창 열기, 저장 ⌘S) · 윈도우(최소화 ⌘M, 확대/축소, 모두 앞으로).
    public func mainMenus() -> [EppMainMenu] {
        let file = NSMenu(title: L("파일"))
        let captureItem = NSMenuItem(title: L("캡처 창 열기"), action: #selector(openLibrary), keyEquivalent: "")
        captureItem.target = self
        file.addItem(captureItem)
        file.addItem(NSMenuItem(title: L("저장…"), action: #selector(NSDocument.save(_:)), keyEquivalent: "s"))

        let window = NSMenu(title: L("윈도우"))
        window.addItem(NSMenuItem(title: L("최소화"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: L("확대/축소"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        window.addItem(NSMenuItem(title: L("모두 앞으로 가져오기"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        return [EppMainMenu(.file, file), EppMainMenu(.window, window)]
    }

    @objc private func closeAllPins() { PinWindow.closeAll() }

    @objc private func openLibrary() {
        if library == nil { library = LibraryWindowController() }
        library?.show()
    }

    // MARK: 캡처

    /// 화면을 찍어 캡처 화면을 띄우기 전까지 참. 그사이 단축키를 또 눌러도 한 번만 시작한다.
    private var isPreparingSession = false

    /// 화면을 멈춰 찍고 오버레이를 띄운다. 오버레이는 포커스를 빼앗지 않으므로 원래 앱이 계속 앞에 있다.
    private func startSession(_ mode: CaptureSession.Mode) {
        guard session == nil else { return }
        guard !isPreparingSession else {
            EventLog.write("캡처 준비 중이라 단축키를 무시함")
            return
        }
        if mode != .whiteboard, !ScreenCapturer.hasPermission { askForPermission(); return }
        rememberFrontApp()
        isPreparingSession = true
        let started = Date()
        Task { @MainActor in
            defer { isPreparingSession = false }
            var shots: [ScreenShot] = []
            do {
                if ScreenCapturer.hasPermission { shots = try await ScreenCapturer.captureAll() }
            } catch {
                EventLog.write("캡처 준비 실패(\(String(format: "%.1f", Date().timeIntervalSince(started)))초): \(error)")
                if mode != .whiteboard { show(error); return }
            }
            // 화이트보드는 권한이 없으면 바깥도 바탕으로 띄운다.
            if shots.isEmpty, mode == .whiteboard {
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                if let screen, let board = ScreenShot.whiteboard(on: screen) { shots = [board] }
            }
            guard !shots.isEmpty else {
                // 예전에는 여기서 말없이 끝나 "단축키가 안 먹는다"로 보였다.
                EventLog.write("캡처 준비 실패: 찍은 화면이 없음(화면 \(NSScreen.screens.count)개)")
                show(CaptureError.noScreens)
                return
            }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > 1.5 { EventLog.write("캡처 준비가 늦음: \(String(format: "%.1f", elapsed))초") }
            guard session == nil else { return }
            session = CaptureSession(shots: shots, mode: mode) { [weak self] result in
                self?.session = nil
                self?.finishCapture(result)
            }
        }
    }

    @objc private func captureArea() { startSession(.area) }
    @objc private func readCode() { startSession(.qr) }

    /// n초 뒤에 영역 캡처를 시작한다. 남은 시간을 보여 주고, 찍기 직전에 알림을 치운다.
    @objc private func captureWithTimer(_ sender: NSMenuItem) { startTimer(seconds: sender.tag) }
    @objc private func captureWithConfiguredTimer() { startTimer(seconds: settings.timerSeconds) }

    @objc private func cancelTimer() {
        guard timerRunning else { return }
        timerGeneration += 1
        timerRunning = false
        Countdown.hide()
        Toast.show(L("타이머를 취소했어요"))
    }

    /// 화면 기록 권한이 없을 때: 시스템에 한 번 묻고, 시작하기 상자와 함께 캡처 설정을 연다(권한 열기 버튼이 있다).
    private func askForPermission() {
        ScreenCapturer.requestPermission()
        context.showGettingStarted()
    }

    private var timerRunning = false
    /// 취소한 뒤 바로 다시 시작해도 이전 타이머가 이어서 세지 않도록 차례 번호로 구분한다.
    private var timerGeneration = 0

    /// 타이머 캡처. 세는 동안 타이머 단축키를 한 번 더 누르거나 메뉴의 "타이머 취소"를 누르면 멈춘다.
    private func startTimer(seconds: Int) {
        if timerRunning {
            cancelTimer()
            return
        }
        guard session == nil else { return }
        if !ScreenCapturer.hasPermission { askForPermission(); return }
        timerRunning = true
        timerGeneration += 1
        let generation = timerGeneration
        var remaining = seconds
        Toast.hide()
        func tick() {
            guard generation == timerGeneration else { return }
            if remaining == 0 {
                Countdown.hide()
                timerRunning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.startSession(.area) }
                return
            }
            Countdown.show(remaining)
            remaining -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick() }
        }
        tick()
    }
    /// 전체 화면 캡처: 기본은 편집 화면 없이 마우스가 있는 화면을 바로 복사하고 탭에 넣는다.
    /// 설정에서 끄면 예전처럼 편집 화면으로 연다.
    @objc private func captureFullScreen() {
        guard settings.fullScreenInstant else { startSession(.fullScreen); return }
        guard session == nil, !isPreparingSession else { return }
        guard ScreenCapturer.hasPermission else { askForPermission(); return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            startSession(.fullScreen)
            return
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        Task { @MainActor in
            do {
                if settings.fullScreenAllDisplays, NSScreen.screens.count > 1 {
                    let shots = try await ScreenCapturer.captureAll()
                    guard let whole = stitchScreens(shots.map { ($0.image, $0.screen.frame, $0.scale) }) else {
                        startSession(.fullScreen)
                        return
                    }
                    save(CaptureResult(image: whole.image, pixelScale: whole.scale,
                                       rect: CGRect(origin: .zero, size: whole.frame.size), displayID: displayID,
                                       screenFrame: whole.frame, remembersArea: false))
                    return
                }
                guard let shot = try await ScreenCapturer.capture(displayID: displayID) else {
                    startSession(.fullScreen)
                    return
                }
                save(CaptureResult(image: shot.image, pixelScale: shot.scale,
                                   rect: CGRect(origin: .zero, size: shot.screen.frame.size),
                                   displayID: displayID, screenFrame: shot.screen.frame))
            } catch {
                show(error)
            }
        }
    }

    /// 지금 앞에 있는 앱의 맨 앞 창을 고른 채 편집 화면을 연다. 창을 못 찾으면 영역 캡처로 시작한다.
    @objc private func captureFrontWindow() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let window = WindowList.frontWindow(preferring: front) else {
            startSession(.area)
            return
        }
        startSession(.window(window.rect, window.name, window.id))
    }
    @objc private func openWhiteboard() { startSession(.whiteboard) }

    /// 마지막으로 고른 영역을 편집 없이 바로 다시 찍어 복사한다.
    @objc private func repeatLastArea() {
        guard session == nil else { return }
        let defaults = GrabbyStorage.defaults
        guard let saved = defaults.string(forKey: lastRectKey), defaults.object(forKey: lastDisplayKey) != nil else {
            captureArea()
            return
        }
        guard ScreenCapturer.hasPermission else { askForPermission(); return }
        let rect = NSRectFromString(saved)
        let displayID = CGDirectDisplayID(defaults.integer(forKey: lastDisplayKey))
        Task { @MainActor in
            do {
                guard let shot = try await ScreenCapturer.capture(displayID: displayID),
                      let image = shot.crop(rect.intersection(CGRect(origin: .zero, size: shot.screen.frame.size))) else {
                    captureArea()
                    return
                }
                save(CaptureResult(image: image, pixelScale: shot.scale, rect: rect, displayID: displayID, screenFrame: shot.screen.frame))
            } catch {
                show(error)
            }
        }
    }

    /// 복사하고 탭에 넣는다. 찍은 자리를 반짝이고 소리를 낸다.
    private func save(_ result: CaptureResult, copy: Bool = true) {
        let (item, pruned) = CaptureStore.shared.add(result.image, scale: result.pixelScale,
                                                     original: result.original, annotations: result.annotations)
        if copy { Clipboard.copy(result.image, scale: result.pixelScale) }
        if !result.isWhiteboard, result.remembersArea {
            GrabbyStorage.defaults.set(NSStringFromRect(result.rect), forKey: lastRectKey)
            GrabbyStorage.defaults.set(Int(result.displayID), forKey: lastDisplayKey)
        }
        CaptureFeedback.flash(result.globalRect)
        let message = !copy ? L("탭에만 남겼어요 · 복사는 하지 않았어요")
            : pruned > 0 ? L("복사했어요 · 오래된 캡처 %ld개를 정리했어요", pruned) : L("복사했어요 · ⌘V로 붙여 넣기")
        if copy {
            Toast.show(message, image: CaptureStore.shared.thumbnail(for: item))
        } else {
            // Esc로 닫아 탭에만 남긴 것은 원치 않았을 수 있으니 바로 되돌릴 수 있게 한다.
            Toast.show(message, image: CaptureStore.shared.thumbnail(for: item), action: (L("되돌리기"), {
                CaptureStore.shared.remove(item)
                Toast.show(L("탭에서 뺐어요"))
            }))
        }
        if settings.openLibraryAfterCapture {
            if library == nil { library = LibraryWindowController() }
            library?.showWithoutFocus()
        }
        CaptureStore.shared.indexText()
    }

    /// 캡처·화이트보드를 마친 뒤 고른 동작을 하고 원래 앱으로 돌아간다.
    private func finishCapture(_ result: CaptureResult?) {
        guard let result else { returnToPreviousApp(); return }
        switch result.action {
        case .ocr:
            // 글자만 복사하고 탭에는 넣지 않는다.
            Task { @MainActor in
                let text = await TextRecognizer.recognize(result.image)
                if text.isEmpty {
                    Toast.show(L("글자를 찾지 못했어요"))
                } else {
                    Clipboard.copy(text: text)
                    let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
                    Toast.show(L("글자를 복사했어요 · %@", String(firstLine.prefix(40))))
                }
                returnToPreviousApp()
            }
        case .qr:
            // 값만 복사하고 탭에는 넣지 않는다.
            Task { @MainActor in
                let values = await CodeReader.read(result.image)
                returnToPreviousApp()
                CodeReader.handle(values)
            }
        case .save:
            save(result)
            ImageSaver.save(result.image, scale: result.pixelScale) { [weak self] in self?.returnToPreviousApp() }
        case .pin:
            save(result)
            PinWindow.show(result.image, scale: result.pixelScale, at: result.globalRect)
            returnToPreviousApp()
        case .copy:
            save(result)
            returnToPreviousApp()
        case .keep:
            save(result, copy: false)
            returnToPreviousApp()
        case .beautify:
            // 탭에는 원래 캡처를 넣고, 클립보드에는 꾸민 이미지를 넣는다.
            save(result)
            Clipboard.copy(Beautifier.apply(result.image, scale: result.pixelScale), scale: result.pixelScale)
            Toast.show(L("꾸며서 복사했어요"))
            returnToPreviousApp()
        }
    }

    private func rememberFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    private func returnToPreviousApp() {
        guard let previousApp else { return }
        self.previousApp = nil
        previousApp.activate()
        // 원래 앱이 앞으로 오면서 탭 창을 덮지 않도록, 포커스는 원래 앱에 둔 채 창만 다시 앞으로 올린다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.library?.showWithoutFocus()
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("캡처하지 못했어요")
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Epp

    public func settingsTabs() -> [EppSettingsTab] { GrabbySettings.tabs(settings: settings) }

    public func makeGettingStarted() -> AnyView? {
        AnyView(GrabbyGettingStarted(store: CaptureStore.shared, settings: settings, openPermissions: context.openPermissions))
    }

    public func globalShortcuts() -> [EppShortcutInfo] {
        HotKeyAction.allCases.compactMap { action in
            settings.hotKeys[action.rawValue].map { EppShortcutInfo(title: action.title, keys: $0.displayText) }
        }
    }

    /// 빠른 검색: 캡처의 메모와 인식한 글자에서 찾는다. 고르면 탭 창에서 그 캡처를 연다.
    public func search(_ query: EppSearchQuery) -> [EppSearchResult] {
        CaptureStore.shared.items.filter { query.matches($0.note, $0.text) }
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map { item in
                let title = item.note?.isEmpty == false ? item.note! : (query.snippet(item.text, length: 60) ?? L("캡처"))
                return EppSearchResult(id: "grabby." + item.id.uuidString, title: title,
                                       detail: item.note?.isEmpty == false ? query.snippet(item.text) : "\(item.width)×\(item.height)",
                                       symbol: "camera.viewfinder", date: item.date) { [weak self] in
                    self?.openLibrary()
                    self?.library?.select(item.id)
                }
            }
    }

    /// epp://grabby/area — 영역 캡처(직접 영역을 골라야 찍힘), epp://grabby/library — 탭 창.
    /// 전체 화면 캡처는 주소로 열지 않는다. 웹페이지나 다른 앱이 묻지 않고 화면을 찍게 되기 때문이다.
    public func handle(url: URL) {
        switch url.pathComponents.dropFirst().first ?? "area" {
        case "area": captureArea()
        case "library": openLibrary()
        default: EppLog.write("캡처", "모르는 주소 명령 무시: \(url.path)")
        }
    }

    public static func runSelfTest() -> Bool { SelfTest.run() == 0 }
}

/// 설정 맨 위 시작하기 상자. 끝낸 단계는 체크로 바뀐다.
struct GrabbyGettingStarted: View {
    let store: CaptureStore
    @ObservedObject var settings: AppSettings
    let openPermissions: () -> Void
    @ObservedObject private var permissions = EppPermissions.shared
    /// 보관함은 바뀜을 알리지 않아서 가끔 다시 본다.
    @State private var captured = 0
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        let keys = settings.hotKeys[HotKeyAction.captureArea.rawValue]?.displayText ?? L("메뉴")
        EppStepList([
            .init(L("화면 기록 권한 허용하기 (Epp 설정 → 일반 → 권한)"), done: permissions.screenRecording,
                  action: (L("권한 열기"), openPermissions)),
            .init(L("%@로 영역을 골라 캡처하기", keys), done: captured >= 1),
            .init(L("캡처 화면에서 그리고 ↩로 복사하기. 탭 창에 모아 둬요."), done: captured >= 2),
        ], footer: L("⇧⌘3·4·5는 macOS 스크린샷과 겹쳐요. 단축키 탭에서 ⌃⌘ 묶음으로 바꿀 수 있어요."))
        .onAppear {
            permissions.refresh()
            captured = store.items.count
        }
        .onReceive(poll) { _ in captured = store.items.count }
    }
}
