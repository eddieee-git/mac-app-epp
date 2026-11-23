import AppKit
import SwiftUI

/// 잠깐 떴다 사라지는 알림 하나. 모든 기능이 같은 모양(둥근 반투명 상자, 13pt 글자)과 같은 동작을 쓴다.
/// - 다른 앱의 포커스를 빼앗지 않는다. 한 번에 하나만(새 알림이 오면 바꾼다).
/// - 버튼(되돌리기 등)이 있으면 누를 수 있게 더 오래 띄운다.
/// - 소리 내어 읽기(VoiceOver)에도 알린다.
@MainActor
public enum EppToast {
    public enum Place {
        /// 마우스가 있는 화면의 아래쪽 가운데
        case bottom
        /// 이 화면 위치를 가운데로
        case center(NSPoint)
        /// 이 창(사각형) 아래쪽 가운데 안쪽
        case below(NSRect)
    }

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    public static var isShowing: Bool { panel?.isVisible == true }

    public static func show(_ message: String, symbol: String? = nil, image: NSImage? = nil,
                            action: (title: String, run: () -> Void)? = nil,
                            place: Place = .bottom, duration: TimeInterval? = nil) {
        hide()
        let view = ToastView(message: message, symbol: symbol, image: image, actionTitle: action?.title) {
            let run = action?.run
            hide()
            run?()
        }
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = ToastPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = action == nil
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.setFrameOrigin(origin(for: size, place: place))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                    MainActor.assumeIsolated {
                        panel.orderOut(nil)
                        if EppToast.panel === panel { EppToast.panel = nil }
                    }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration ?? (action == nil ? 1.4 : 5)), execute: work)
    }

    /// 바로 치운다(캡처에 알림이 찍히지 않게 등).
    public static func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func origin(for size: NSSize, place: Place) -> NSPoint {
        func screen(containing point: NSPoint) -> NSRect {
            (NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        }
        let target: NSPoint
        let visible: NSRect
        switch place {
        case .bottom:
            visible = screen(containing: NSEvent.mouseLocation)
            target = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 80)
        case .center(let point):
            visible = screen(containing: point)
            target = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        case .below(let frame):
            visible = screen(containing: NSPoint(x: frame.midX, y: frame.midY))
            target = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 12)
        }
        return NSPoint(x: min(max(target.x, visible.minX + 8), visible.maxX - size.width - 8),
                       y: min(max(target.y, visible.minY + 8), visible.maxY - size.height - 8))
    }
}

/// 테두리 없는 창은 기본으로 버튼을 누를 수 없어서 키 창이 될 수 있게 한다(앱을 앞으로 가져오지는 않는다).
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ToastView: View {
    let message: String
    let symbol: String?
    let image: NSImage?
    let actionTitle: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 56, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(symbol.hasPrefix("checkmark") ? Color.green : Color.secondary)
            }
            Text(message)
            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
