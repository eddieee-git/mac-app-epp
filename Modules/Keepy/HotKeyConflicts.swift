import AppKit

/// 단축키가 겹칠 수 있는 상대. macOS는 다른 앱이 쓰는 단축키를 알려 주지 않아서,
/// 알려진 클립보드 기록 앱이 켜져 있는지만 확인한다.
enum HotKeyConflicts {
    /// 번들 ID 앞부분 → 앱 이름
    private static let clipboardApps: [(prefix: String, name: String)] = [
        ("com.eddieee.Keepy", "Keepy"),
        ("org.p0deje.Maccy", "Maccy"),
        ("com.wiheads.paste", "Paste"),
        ("com.raycast.macos", "Raycast"),
        ("com.clipy-app.Clipy", "Clipy"),
        ("com.fiplab.copyclip", "CopyClip"),
        ("com.runningwithcrayons.Alfred", "Alfred"),
        ("com.lowtechguys.Clop", "Clop"),
    ]

    /// 지금 켜져 있는 클립보드 기록 앱 이름들. 단독 Keepy 앱도 포함한다(같은 ⌃⌥V를 쓴다).
    static var runningClipboardApps: [String] {
        let ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return clipboardApps.filter { app in ids.contains { $0.hasPrefix(app.prefix) } }.map(\.name)
    }
}
