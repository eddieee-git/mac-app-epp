import AppKit

/// Epp 전체가 같이 쓰는 언어. 설정 → 일반 → 언어에서 고른다.
/// 기능마다 자기 `L()`과 영어 사전을 갖고, 한국어인지는 여기서 정한다.
public enum EppLanguage {
    public static let key = "language"

    /// 설정에서 고른 언어. 고르지 않았으면 Mac 언어 목록에 한국어가 있을 때 한국어, 없으면 영어로 시작한다.
    /// 문구는 시작할 때 한 번 정해지므로 바꾸면 Epp를 다시 열어야 한다.
    /// 켤 때 한 번 정한다. 시험에서만 바꾼다.
    nonisolated(unsafe) public static var isKorean: Bool = {
        if let forced = UserDefaults.standard.string(forKey: key) { return forced.hasPrefix("ko") }
        // Mac 언어 목록에 한국어가 있으면(첫 번째가 아니어도) 한국어로 시작한다.
        return Locale.preferredLanguages.isEmpty || Locale.preferredLanguages.contains { $0.hasPrefix("ko") }
    }()
}

public enum EppApp {
    /// Epp를 끝내고 다시 연다(언어는 다시 열어야 바뀐다).
    @MainActor
    public static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// esc로 닫히는 창 (설정, 시작 안내)
public final class EscClosableWindow: NSWindow {
    override public func cancelOperation(_ sender: Any?) { performClose(sender) }
}
