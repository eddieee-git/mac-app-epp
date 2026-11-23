import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 비활성화 패널이라도 검색창 입력을 받으려면 키 윈도우가 될 수 있어야 한다.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 단축키로 띄우는 기록 패널. `.nonactivatingPanel`이라 앞에 있던 앱이
/// 계속 활성 상태로 남아서, 닫은 뒤 ⌘V가 그 앱으로 들어간다.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let viewModel: PanelViewModel
    private let panel: KeyablePanel
    private let onPick: (ClipItem, Bool) -> Void
    private var keyMonitor: Any?

    init(store: HistoryStore, onPick: @escaping (ClipItem, Bool) -> Void) {
        self.onPick = onPick
        viewModel = PanelViewModel(store: store)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: HistoryView.size.width, height: HistoryView.size.height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        super.init()
        configurePanel()
    }

    private func configurePanel() {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active

        let host = NSHostingView(rootView: HistoryView(vm: viewModel) { [weak self] item, plain in
            self?.onPick(item, plain)
        })
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    var isVisible: Bool { panel.isVisible }
    /// 마지막으로 띄운 자리의 가운데. 복사 알림을 같은 자리에 띄운다.
    var lastCenter: NSPoint { NSPoint(x: panel.frame.midX, y: panel.frame.midY) }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(copyOnly: Bool = false) {
        viewModel.copyOnly = copyOnly
        viewModel.prepareForShow()
        position()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        removeKeyMonitor()
        viewModel.store.commitDeletion()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size

        var origin: NSPoint
        switch AppSettings.shared.panelPosition {
        case .mouse:
            origin = NSPoint(x: mouse.x - 20, y: mouse.y - size.height + 20)
        case .center:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.1)
        }
        origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
        origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: - 키보드

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// true를 돌려주면 이벤트를 쓴 것으로 보고 검색창으로 보내지 않는다.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch Int(event.keyCode) {
        case kVK_Escape:
            if viewModel.query.isEmpty { hide() } else { viewModel.query = "" }
            return true
        case kVK_DownArrow:
            viewModel.move(by: 1); return true
        case kVK_UpArrow:
            viewModel.move(by: -1); return true
        case kVK_PageDown:
            viewModel.move(by: 8); return true
        case kVK_PageUp:
            viewModel.move(by: -8); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = viewModel.selectedItem { onPick(item, flags.contains(.option)) }
            return true
        case kVK_Delete where flags.contains(.command):
            viewModel.deleteSelected(); return true
        default:
            break
        }

        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        if let number = Int(key), (1...9).contains(number) {
            let items = viewModel.visibleItems
            if items.indices.contains(number - 1) {
                onPick(items[number - 1], flags.contains(.option))
            }
            return true
        }
        switch key {
        case "p": viewModel.togglePinSelected(); return true
        case "z": viewModel.undoDelete(); return true
        case "w": hide(); return true
        case ",": hide(); return false
        default: return false
        }
    }
}
