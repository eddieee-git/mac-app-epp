import AppKit

/// 기능의 관리·목록 창(스티커 관리, 타이머 목록, 캡처 보관함, Epp 설정)을 같은 모양·동작으로 맞춘다.
/// - 제목 막대·닫기·최소화(설정 창 제외 크기 조절), 지금 보는 데스크톱(Space)에 열기, 전체 화면 앱 위에도 열기
/// - 창 크기·자리를 기억(`Epp.<이름>`), 처음에는 화면 가운데
/// - Epp를 쓰는 동안에는 떠 있는 스티커·시계 위에 보이고, 다른 앱으로 가면 보통 창으로 내려간다
/// 창은 모두 메인 스레드에서 다룬다(부르는 쪽이 메인 스레드라고 보고 확인한다).
public enum EppWindows {
    public static func prepare(_ window: NSWindow, autosaveName: String, minSize: NSSize? = nil, resizable: Bool = true,
                               floatsWhileActive: Bool = true) {
        MainActor.assumeIsolated {
        window.styleMask.formUnion([.titled, .closable, .miniaturizable])
        if resizable { window.styleMask.insert(.resizable) }
        window.isReleasedWhenClosed = false
        if let minSize { window.minSize = minSize }
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let name = "Epp." + autosaveName
        if !window.setFrameUsingName(name) { window.center() }
        window.setFrameAutosaveName(name)
        if floatsWhileActive { floatWhileActive(window) }
        }
    }

    /// Epp를 앞으로 가져와 창을 연다.
    public static func show(_ window: NSWindow?) {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    nonisolated(unsafe) private static var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    /// Epp가 앞에 있는 동안만 떠 있게 한다(항상 위 스티커에 가려지지 않게). 다른 앱으로 가면 보통 창.
    public static func floatWhileActive(_ window: NSWindow) {
        MainActor.assumeIsolated { floatWhileActiveOnMain(window) }
    }

    @MainActor private static func floatWhileActiveOnMain(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard observers[key] == nil else { return }
        window.level = NSApp.isActive ? .floating : .normal
        let center = NotificationCenter.default
        observers[key] = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak window] _ in
                window?.level = .floating
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak window] _ in
                window?.level = .normal
            },
        ]
    }

    /// 창을 버릴 때(기능을 끌 때) 관찰을 거둔다.
    public static func forget(_ window: NSWindow) {
        observers.removeValue(forKey: ObjectIdentifier(window))?.forEach(NotificationCenter.default.removeObserver)
    }
}
