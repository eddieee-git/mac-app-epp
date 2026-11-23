import AppKit

/// 붙여 넣지 않고 복사만 했을 때 잠깐 띄우는 "복사했어요" 알림.
/// 메뉴바 아이콘은 가려져 있을 수 있어서(노치, 메뉴바 정리 앱) 화면에 직접 띄운다.
@MainActor
enum CopiedToast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// center: 알림을 띄울 화면 위치(기록 창이 있던 자리의 가운데)
    static func show(at center: NSPoint) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: L("복사했어요"), .priority: NSAccessibilityPriorityLevel.high.rawValue])

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let size = NSSize(width: 150, height: 44)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12

        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        icon.contentTintColor = .systemGreen
        let label = NSTextField(labelWithString: L("복사했어요"))
        label.font = .systemFont(ofSize: 14, weight: .medium)
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
        panel.contentView = effect
        return panel
    }
}
