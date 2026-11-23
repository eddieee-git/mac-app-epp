import AppKit

/// Epp 전체가 같이 쓰는 언어. 설정 → 일반 → 언어에서 고른다.
/// 기능마다 자기 `L()`과 영어 사전을 갖고, 한국어인지는 여기서 정한다.
public enum EppLanguage {
    public static let key = "language"

    /// 설정에서 고른 언어. 고르지 않았으면 Mac 언어를 따르고, 한국어가 아니면 영어로 시작한다.
    /// 문구는 시작할 때 한 번 정해지므로 바꾸면 Epp를 다시 열어야 한다.
    /// 켤 때 한 번 정한다. 시험에서만 바꾼다.
    nonisolated(unsafe) public static var isKorean: Bool = {
        if let forced = UserDefaults.standard.string(forKey: key) { return forced.hasPrefix("ko") }
        return Locale.preferredLanguages.first?.hasPrefix("ko") ?? true
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
