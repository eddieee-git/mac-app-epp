import Foundation

/// Peeky가 쓰는 저장 위치. PeekyModule이 시작할 때 Epp가 준 값으로 채운다.
/// 여러 스레드(메뉴바 훑기)에서 읽지만 시작할 때 한 번만 쓴다.
enum PeekyStorage {
    /// Peeky 설정(Epp의 기능별 UserDefaults). 점검할 때는 임시 저장소.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard
    /// 진단 로그 파일 (~/Library/Logs/<Epp 이름> Peeky.log)
    nonisolated(unsafe) static var logPath = NSHomeDirectory() + "/Library/Logs/Epp Peeky.log"
}
