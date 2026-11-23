import Foundation

/// Epp 전체가 같이 쓰는 진단 로그. 설정 → 일반 → 문제 해결 → "진단 로그 남기기"를 켰을 때만 쓴다.
/// 파일 하나(~/Library/Logs/<Epp 이름>.log)에 기능 이름을 앞에 붙여 한 줄씩 더한다. Epp를 켤 때 새로 쓴다.
/// 권한·동작 문제를 볼 때 쓰는 것이라 복사한 내용 같은 개인 내용은 적지 않는다.
public enum EppLog {
    public static let enabledKey = "diagnosticLog"
    /// 본체가 시작할 때 앱 이름("Epp" / "Epp Dev")에 맞게 정한다.
    nonisolated(unsafe) public static var path = NSHomeDirectory() + "/Library/Logs/Epp.log"
    private static let lock = NSLock()

    public static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// source: 기능 이름이나 "Epp"
    public static func write(_ source: String, _ line: String) {
        guard isOn else { return }
        let text = "\(Date()) [\(source)] \(line)\n"
        lock.lock()
        defer { lock.unlock() }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// 오류: 진단 로그가 꺼져 있어도 시스템 로그(Console 앱)에는 남긴다.
    public static func error(_ source: String, _ line: String) {
        NSLog("Epp [\(source)] \(line)")
        write(source, line)
    }

    /// 로그 파일을 지운다(Epp를 켤 때, 진단 로그를 끌 때).
    public static func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(atPath: path)
    }
}
